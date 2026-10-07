#![cfg(feature = "http")]

//! Bidirectional web share: a browser that opened the share link uploads
//! files back to the sharing device.

use localsend::http::server::common::save::FileUploadTarget;
use localsend::http::server::v2::{
    PrepareUploadDecisionV2, ServerEventV2, SessionEndReasonV2, WEB_UPLOAD_FINGERPRINT_PREFIX,
};
use localsend::http::server::web::{WebSendConfig, WebSendEvent, WebSendI18n};
use localsend::http::server::{start_with_port, ServerConfigV2};
use localsend::http::state::ClientInfo;
use localsend::model::discovery::DeviceType;
use localsend::reqwest;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU16, Ordering};
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

/// What the fake application does with incoming web uploads.
#[derive(Clone)]
enum UploadBehavior {
    /// Accept every file and let the server write it into this directory.
    AcceptInto(PathBuf),
    /// Accept every file but write it to this exact path (e.g. `/dev/full`).
    AcceptToFixedPath(PathBuf),
    /// Decline the request.
    Decline,
}

/// Events observed by the fake application.
#[derive(Debug)]
enum Observed {
    PrepareUpload {
        fingerprint: String,
        device_type: Option<DeviceType>,
        cert_fingerprint: Option<String>,
        file_names: Vec<String>,
        previews: Vec<Option<String>>,
    },
    SessionEnd(SessionEndReasonV2),
}

struct TestServer {
    base: String,
    observed: mpsc::UnboundedReceiver<Observed>,
    _stop_tx: oneshot::Sender<()>,
}

async fn start(behavior: UploadBehavior, accept_web: bool) -> TestServer {
    start_with_options(behavior, accept_web, false).await.0
}

/// Starts a server with web send enabled. When `hold` is true, the
/// prepare-upload decision is only sent once the returned sender is used.
async fn start_with_options(
    behavior: UploadBehavior,
    accept_web: bool,
    hold: bool,
) -> (TestServer, Option<mpsc::UnboundedSender<()>>) {
    let _ = tracing_subscriber::fmt().with_test_writer().try_init();
    let port = free_port();

    let (web_event_tx, mut web_event_rx) = mpsc::channel::<WebSendEvent>(16);
    tokio::spawn(async move {
        while let Some(event) = web_event_rx.recv().await {
            if let WebSendEvent::PrepareDownload { decision_tx, .. } = event {
                let _ = decision_tx.send(accept_web);
            }
        }
    });

    let (observed_tx, observed_rx) = mpsc::unbounded_channel();
    let (release_tx, mut release_rx) = mpsc::unbounded_channel::<()>();
    let (v2_event_tx, mut v2_event_rx) = mpsc::channel::<ServerEventV2>(16);
    tokio::spawn(async move {
        while let Some(event) = v2_event_rx.recv().await {
            match event {
                ServerEventV2::PrepareUpload {
                    info,
                    cert_fingerprint,
                    files,
                    decision_tx,
                    ..
                } => {
                    let _ = observed_tx.send(Observed::PrepareUpload {
                        fingerprint: info.fingerprint.clone(),
                        device_type: info.device_type.clone(),
                        cert_fingerprint,
                        file_names: files.values().map(|f| f.file_name.clone()).collect(),
                        previews: files.values().map(|f| f.preview.clone()).collect(),
                    });
                    if hold {
                        release_rx.recv().await;
                    }
                    let decision = match behavior {
                        UploadBehavior::Decline => PrepareUploadDecisionV2::Decline,
                        _ => PrepareUploadDecisionV2::Accept(
                            files.keys().cloned().collect::<HashSet<_>>(),
                        ),
                    };
                    let _ = decision_tx.send(decision);
                }
                ServerEventV2::FileUpload {
                    file, target_tx, ..
                } => {
                    let path = match &behavior {
                        UploadBehavior::AcceptInto(dir) => dir.join(&file.file_name),
                        UploadBehavior::AcceptToFixedPath(path) => path.clone(),
                        UploadBehavior::Decline => unreachable!(),
                    };
                    let (result_tx, _result_rx) = oneshot::channel();
                    let _ = target_tx.send(FileUploadTarget::Path {
                        path,
                        result_tx,
                        progress_tx: None,
                    });
                }
                ServerEventV2::SessionEnd { reason, .. } => {
                    let _ = observed_tx.send(Observed::SessionEnd(reason));
                }
                _ => {}
            }
        }
    });

    let (stop_tx, stop_rx) = oneshot::channel();
    start_with_port(
        port,
        None,
        ClientInfo {
            alias: "Host".to_string(),
            version: "2.1".to_string(),
            device_model: None,
            device_type: None,
            token: "host-fingerprint".to_string(),
            app_build: None,
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            event_tx: v2_event_tx,
        }),
        Some(WebSendConfig {
            files: HashMap::new(),
            pin: None,
            i18n: WebSendI18n::default(),
            event_tx: web_event_tx,
        }),
        stop_rx,
    )
    .await
    .expect("Failed to start server");

    wait_until_reachable(port).await;

    (
        TestServer {
            base: format!("http://127.0.0.1:{port}/api/localsend/v2"),
            observed: observed_rx,
            _stop_tx: stop_tx,
        },
        hold.then_some(release_tx),
    )
}

fn free_port() -> u16 {
    static PORT_COUNTER: AtomicU16 = AtomicU16::new(42551);
    loop {
        let port = PORT_COUNTER.fetch_add(1, Ordering::SeqCst);
        if std::net::TcpListener::bind(("127.0.0.1", port)).is_ok() {
            return port;
        }
    }
}

async fn wait_until_reachable(port: u16) {
    for _ in 0..100 {
        if tokio::net::TcpStream::connect(("127.0.0.1", port))
            .await
            .is_ok()
        {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("Server did not become reachable on port {port}");
}

fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("aika-web-upload-{name}-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Opens the share link like the web page does and returns the session ID.
async fn open_link(client: &reqwest::Client, base: &str) -> (u16, Option<String>) {
    let res = client
        .post(format!("{base}/prepare-download"))
        .send()
        .await
        .unwrap();
    let status = res.status().as_u16();
    let body: Option<Value> = res.json().await.ok();
    let session_id = body.and_then(|b| b["sessionId"].as_str().map(str::to_string));
    (status, session_id)
}

async fn prepare_upload(
    client: &reqwest::Client,
    base: &str,
    session_id: &str,
    files: Value,
) -> (u16, Value) {
    let res = client
        .post(format!("{base}/web/prepare-upload?sessionId={session_id}"))
        .json(&json!({ "files": files }))
        .send()
        .await
        .unwrap();
    let status = res.status().as_u16();
    let body = res.json().await.unwrap_or(Value::Null);
    (status, body)
}

async fn upload(
    client: &reqwest::Client,
    base: &str,
    session_id: &str,
    file_id: &str,
    token: &str,
    content: &'static [u8],
) -> u16 {
    client
        .post(format!(
            "{base}/upload?sessionId={session_id}&fileId={file_id}&token={token}"
        ))
        .body(content)
        .send()
        .await
        .unwrap()
        .status()
        .as_u16()
}

#[tokio::test]
async fn test_web_upload_full_flow() {
    let dir = temp_dir("full");
    let mut server = start(UploadBehavior::AcceptInto(dir.clone()), true).await;
    let client = reqwest::Client::new();

    let (status, web_session) = open_link(&client, &server.base).await;
    assert_eq!(status, 200);
    let web_session = web_session.unwrap();

    let (status, body) = prepare_upload(
        &client,
        &server.base,
        &web_session,
        json!({
            "a": { "id": "a", "fileName": "hello.txt", "size": 5, "fileType": "text/plain", "modified": "2026-01-02T03:04:05Z" },
            "b": { "id": "b", "fileName": "photo été.jpg", "size": 3 }
        }),
    )
    .await;
    assert_eq!(status, 200, "{body}");

    match server.observed.recv().await.unwrap() {
        Observed::PrepareUpload {
            fingerprint,
            device_type,
            cert_fingerprint,
            mut file_names,
            previews,
        } => {
            assert_eq!(
                fingerprint,
                format!("{WEB_UPLOAD_FINGERPRINT_PREFIX}{web_session}")
            );
            assert_eq!(device_type, Some(DeviceType::Web));
            assert_eq!(cert_fingerprint, None);
            file_names.sort();
            assert_eq!(file_names, vec!["hello.txt", "photo été.jpg"]);
            assert!(previews.iter().all(Option::is_none));
        }
        other => panic!("unexpected {other:?}"),
    }

    let upload_session = body["sessionId"].as_str().unwrap().to_string();
    let token_a = body["files"]["a"].as_str().unwrap().to_string();
    let token_b = body["files"]["b"].as_str().unwrap().to_string();

    assert_eq!(
        upload(
            &client,
            &server.base,
            &upload_session,
            "a",
            &token_a,
            b"hello"
        )
        .await,
        200
    );
    // A token can only be used once.
    assert_eq!(
        upload(
            &client,
            &server.base,
            &upload_session,
            "a",
            &token_a,
            b"hello"
        )
        .await,
        403
    );
    assert_eq!(
        upload(
            &client,
            &server.base,
            &upload_session,
            "b",
            &token_b,
            b"abc"
        )
        .await,
        200
    );

    match server.observed.recv().await.unwrap() {
        Observed::SessionEnd(reason) => assert_eq!(reason, SessionEndReasonV2::Finished),
        other => panic!("unexpected {other:?}"),
    }

    assert_eq!(std::fs::read(dir.join("hello.txt")).unwrap(), b"hello");
    assert_eq!(std::fs::read(dir.join("photo été.jpg")).unwrap(), b"abc");
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn test_web_upload_requires_accepted_session() {
    let dir = temp_dir("unaccepted");
    let server = start(UploadBehavior::AcceptInto(dir.clone()), false).await;
    let client = reqwest::Client::new();

    // The host declines the web client: no session to upload with.
    let (status, _) = open_link(&client, &server.base).await;
    assert_eq!(status, 403);

    let files = json!({ "a": { "id": "a", "fileName": "x.bin", "size": 1 } });
    let (status, _) = prepare_upload(&client, &server.base, "127.0.0.1", files.clone()).await;
    assert_eq!(status, 403);

    let (status, _) = prepare_upload(&client, &server.base, "forged", files).await;
    assert_eq!(status, 403);

    let res = client
        .post(format!("{}/web/prepare-upload", server.base))
        .json(&json!({ "files": {} }))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status().as_u16(), 400);
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn test_web_upload_rejects_invalid_files() {
    let dir = temp_dir("invalid");
    let server = start(UploadBehavior::AcceptInto(dir.clone()), true).await;
    let client = reqwest::Client::new();
    let (_, web_session) = open_link(&client, &server.base).await;
    let web_session = web_session.unwrap();

    for name in [
        "../evil.sh",
        "dir/file.txt",
        "..\\\\evil",
        "..",
        ".",
        "  ",
        "bad\u{0}name",
        &"a".repeat(300),
    ] {
        let (status, _) = prepare_upload(
            &client,
            &server.base,
            &web_session,
            json!({ "a": { "id": "a", "fileName": name, "size": 1 } }),
        )
        .await;
        assert_eq!(status, 422, "file name {name:?} must be refused");
    }

    // Key and id must match.
    let (status, _) = prepare_upload(
        &client,
        &server.base,
        &web_session,
        json!({ "a": { "id": "b", "fileName": "ok.txt", "size": 1 } }),
    )
    .await;
    assert_eq!(status, 400);

    // No files at all.
    let (status, _) = prepare_upload(&client, &server.base, &web_session, json!({})).await;
    assert_eq!(status, 400);

    // Too many files in one batch.
    let many: serde_json::Map<String, Value> = (0..501)
        .map(|i| {
            let id = format!("f{i}");
            (id.clone(), json!({ "id": id, "fileName": "x", "size": 1 }))
        })
        .collect();
    let (status, _) =
        prepare_upload(&client, &server.base, &web_session, Value::Object(many)).await;
    assert_eq!(status, 413);

    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn test_public_prepare_upload_cannot_spoof_web_marker() {
    let dir = temp_dir("spoof");
    let server = start(UploadBehavior::AcceptInto(dir.clone()), true).await;
    let client = reqwest::Client::new();

    let res = client
        .post(format!("{}/prepare-upload", server.base))
        .json(&json!({
            "info": {
                "alias": "Mallory",
                "version": "2.1",
                "deviceType": "web",
                "fingerprint": format!("{WEB_UPLOAD_FINGERPRINT_PREFIX}127.0.0.1"),
                "port": 53317,
                "protocol": "http"
            },
            "files": { "a": { "id": "a", "fileName": "x.bin", "size": 1, "fileType": "application/octet-stream" } }
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status().as_u16(), 400);
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn test_web_upload_declined_by_host() {
    let dir = temp_dir("declined");
    let server = start(UploadBehavior::Decline, true).await;
    let client = reqwest::Client::new();
    let (_, web_session) = open_link(&client, &server.base).await;

    let (status, _) = prepare_upload(
        &client,
        &server.base,
        &web_session.unwrap(),
        json!({ "a": { "id": "a", "fileName": "x.bin", "size": 1 } }),
    )
    .await;
    assert_eq!(status, 403);
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn test_concurrent_web_upload_gets_conflict_then_succeeds() {
    let dir = temp_dir("concurrent");
    let (mut server, release) =
        start_with_options(UploadBehavior::AcceptInto(dir.clone()), true, true).await;
    let release = release.unwrap();
    let client = reqwest::Client::new();
    let (_, web_session) = open_link(&client, &server.base).await;
    let web_session = web_session.unwrap();

    // First batch: waits for the (held) decision and occupies the slot.
    let first = tokio::spawn({
        let client = client.clone();
        let base = server.base.clone();
        let web_session = web_session.clone();
        async move {
            prepare_upload(
                &client,
                &base,
                &web_session,
                json!({ "a": { "id": "a", "fileName": "first.txt", "size": 5 } }),
            )
            .await
        }
    });
    assert!(matches!(
        server.observed.recv().await.unwrap(),
        Observed::PrepareUpload { .. }
    ));

    // Another batch (e.g. from another device) is refused while the slot is taken.
    let (status, _) = prepare_upload(
        &client,
        &server.base,
        &web_session,
        json!({ "b": { "id": "b", "fileName": "second.txt", "size": 1 } }),
    )
    .await;
    assert_eq!(status, 409);

    release.send(()).unwrap();
    let (status, body) = first.await.unwrap();
    assert_eq!(status, 200);
    let upload_session = body["sessionId"].as_str().unwrap();
    let token = body["files"]["a"].as_str().unwrap();
    assert_eq!(
        upload(&client, &server.base, upload_session, "a", token, b"first").await,
        200
    );
    assert!(matches!(
        server.observed.recv().await.unwrap(),
        Observed::SessionEnd(SessionEndReasonV2::Finished)
    ));

    // The slot is free again: the queued batch now goes through.
    let retry = tokio::spawn({
        let client = client.clone();
        let base = server.base.clone();
        async move {
            prepare_upload(
                &client,
                &base,
                &web_session,
                json!({ "b": { "id": "b", "fileName": "second.txt", "size": 1 } }),
            )
            .await
        }
    });
    assert!(matches!(
        server.observed.recv().await.unwrap(),
        Observed::PrepareUpload { .. }
    ));
    release.send(()).unwrap();
    assert_eq!(retry.await.unwrap().0, 200);
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn test_web_upload_cancel_frees_slot() {
    let dir = temp_dir("cancel");
    let mut server = start(UploadBehavior::AcceptInto(dir.clone()), true).await;
    let client = reqwest::Client::new();
    let (_, web_session) = open_link(&client, &server.base).await;
    let web_session = web_session.unwrap();

    let (status, body) = prepare_upload(
        &client,
        &server.base,
        &web_session,
        json!({ "a": { "id": "a", "fileName": "a.txt", "size": 1 }, "b": { "id": "b", "fileName": "b.txt", "size": 1 } }),
    )
    .await;
    assert_eq!(status, 200);
    let _ = server.observed.recv().await;
    let upload_session = body["sessionId"].as_str().unwrap();

    let res = client
        .post(format!("{}/cancel?sessionId={upload_session}", server.base))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status().as_u16(), 200);
    assert!(matches!(
        server.observed.recv().await.unwrap(),
        Observed::SessionEnd(SessionEndReasonV2::Cancelled)
    ));

    let (status, _) = prepare_upload(
        &client,
        &server.base,
        &web_session,
        json!({ "c": { "id": "c", "fileName": "c.txt", "size": 1 } }),
    )
    .await;
    assert_eq!(status, 200);
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test]
async fn test_web_upload_truncated_body_fails() {
    let dir = temp_dir("truncated");
    let mut server = start(UploadBehavior::AcceptInto(dir.clone()), true).await;
    let client = reqwest::Client::new();
    let (_, web_session) = open_link(&client, &server.base).await;

    let (_, body) = prepare_upload(
        &client,
        &server.base,
        &web_session.unwrap(),
        json!({ "a": { "id": "a", "fileName": "a.bin", "size": 10 } }),
    )
    .await;
    let _ = server.observed.recv().await;
    let upload_session = body["sessionId"].as_str().unwrap();
    let token = body["files"]["a"].as_str().unwrap();

    // Fewer bytes than announced (e.g. connection interrupted).
    assert_eq!(
        upload(&client, &server.base, upload_session, "a", token, b"short").await,
        500
    );
    assert!(matches!(
        server.observed.recv().await.unwrap(),
        Observed::SessionEnd(SessionEndReasonV2::Finished)
    ));
    let _ = std::fs::remove_dir_all(dir);
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn test_web_upload_disk_full_reports_507() {
    if !std::path::Path::new("/dev/full").exists() {
        return;
    }
    let mut server = start(
        UploadBehavior::AcceptToFixedPath(PathBuf::from("/dev/full")),
        true,
    )
    .await;
    let client = reqwest::Client::new();
    let (_, web_session) = open_link(&client, &server.base).await;

    let (_, body) = prepare_upload(
        &client,
        &server.base,
        &web_session.unwrap(),
        json!({ "a": { "id": "a", "fileName": "big.bin", "size": 5 } }),
    )
    .await;
    let _ = server.observed.recv().await;
    let upload_session = body["sessionId"].as_str().unwrap();
    let token = body["files"]["a"].as_str().unwrap();

    assert_eq!(
        upload(&client, &server.base, upload_session, "a", token, b"12345").await,
        507
    );
}
