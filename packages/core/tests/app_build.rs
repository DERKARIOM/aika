#![cfg(feature = "http")]

//! The optional `appBuild` field exchanged during `prepare-upload` (update
//! hint between Aika devices): read when present, never required, and never
//! able to make a transfer fail.

use localsend::http::client::LsHttpClientV2;
use localsend::http::dto::ProtocolType;
use localsend::http::dto_v2::{PrepareUploadRequestDtoV2, ProtocolTypeV2, RegisterDtoV2};
use localsend::http::server::v2::{PrepareUploadDecisionV2, ServerEventV2};
use localsend::http::server::{start_with_port, ServerConfigV2};
use localsend::http::state::ClientInfo;
use localsend::model::transfer::FileDto;
use localsend::reqwest;
use serde_json::json;
use std::sync::atomic::{AtomicU16, Ordering};
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

struct TestServer {
    port: u16,
    /// The `app_build` of each received prepare-upload request.
    sender_builds: mpsc::UnboundedReceiver<Option<u32>>,
    _stop_tx: oneshot::Sender<()>,
}

async fn start(app_build: Option<u32>) -> TestServer {
    let port = free_port();
    let (event_tx, mut event_rx) = mpsc::channel::<ServerEventV2>(16);
    let (builds_tx, sender_builds) = mpsc::unbounded_channel();

    tokio::spawn(async move {
        while let Some(event) = event_rx.recv().await {
            if let ServerEventV2::PrepareUpload {
                info, decision_tx, ..
            } = event
            {
                let _ = builds_tx.send(info.app_build);
                // Declined: only the handshake matters here, and it frees
                // the session slot for the next request.
                let _ = decision_tx.send(PrepareUploadDecisionV2::Decline);
            }
        }
    });

    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    start_with_port(
        port,
        None,
        ClientInfo {
            alias: "Receiver".to_string(),
            version: "2.1".to_string(),
            device_model: None,
            device_type: None,
            token: "receiver-fingerprint".to_string(),
            app_build,
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            event_tx,
        }),
        None,
        stop_rx,
    )
    .await
    .expect("Failed to start server");
    wait_until_reachable(port).await;

    TestServer {
        port,
        sender_builds,
        _stop_tx: stop_tx,
    }
}

fn free_port() -> u16 {
    static PORT_COUNTER: AtomicU16 = AtomicU16::new(41851);
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

fn file() -> FileDto {
    FileDto {
        id: "f".to_string(),
        file_name: "a.txt".to_string(),
        size: 1,
        file_type: "text/plain".to_string(),
        sha256: None,
        preview: None,
        metadata: None,
    }
}

/// Accepts the request so the response carries a body.
async fn start_accepting(app_build: Option<u32>) -> (u16, oneshot::Sender<()>) {
    let port = free_port();
    let (event_tx, mut event_rx) = mpsc::channel::<ServerEventV2>(16);
    tokio::spawn(async move {
        while let Some(event) = event_rx.recv().await {
            if let ServerEventV2::PrepareUpload {
                files, decision_tx, ..
            } = event
            {
                let _ = decision_tx.send(PrepareUploadDecisionV2::Accept(
                    files.keys().cloned().collect(),
                ));
            }
        }
    });
    let (stop_tx, stop_rx) = oneshot::channel::<()>();
    start_with_port(
        port,
        None,
        ClientInfo {
            alias: "Receiver".to_string(),
            version: "2.1".to_string(),
            device_model: None,
            device_type: None,
            token: "receiver-fingerprint".to_string(),
            app_build,
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            event_tx,
        }),
        None,
        stop_rx,
    )
    .await
    .unwrap();
    wait_until_reachable(port).await;
    (port, stop_tx)
}

fn sender(app_build: Option<u32>) -> RegisterDtoV2 {
    RegisterDtoV2 {
        alias: "Sender".to_string(),
        version: "2.1".to_string(),
        device_model: None,
        device_type: None,
        fingerprint: "sender-fingerprint".to_string(),
        port: 53317,
        protocol: ProtocolTypeV2::Http,
        download: false,
        app_build,
    }
}

#[tokio::test]
async fn builds_are_exchanged_both_ways() {
    let (port, _stop) = start_accepting(Some(20)).await;
    let client = LsHttpClientV2::try_new_without_cert().unwrap();
    let result = client
        .prepare_upload(
            ProtocolType::Http,
            "127.0.0.1",
            port,
            None,
            PrepareUploadRequestDtoV2 {
                info: sender(Some(18)),
                files: [("f".to_string(), file())].into(),
            },
            None,
        )
        .await
        .unwrap();
    assert_eq!(result.status_code, 200);
    assert_eq!(result.response.unwrap().app_build, Some(20));
}

#[tokio::test]
async fn receiver_without_build_omits_the_field() {
    let (port, _stop) = start_accepting(None).await;
    let body: serde_json::Value = reqwest::Client::new()
        .post(format!(
            "http://127.0.0.1:{port}/api/localsend/v2/prepare-upload"
        ))
        .json(&json!({
            "info": {"alias": "Old", "version": "2.1", "fingerprint": "x", "port": 1, "protocol": "http"},
            "files": {"f": {"id": "f", "fileName": "a.txt", "size": 1, "fileType": "text/plain"}}
        }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(body.get("sessionId").is_some());
    // Exactly what older versions answer.
    assert!(body.get("appBuild").is_none());
}

#[tokio::test]
async fn sender_build_is_read_leniently() {
    let mut server = start(Some(20)).await;
    let client = reqwest::Client::new();
    let url = format!(
        "http://127.0.0.1:{}/api/localsend/v2/prepare-upload",
        server.port
    );

    // Old Aika / LocalSend (no field), valid, and invalid values: the
    // request is always parsed, invalid builds are simply unknown.
    let cases = [
        (None, None),
        (Some(json!(18)), Some(18)),
        (Some(json!("19")), Some(19)),
        (Some(json!("abc")), None),
        (Some(json!(-4)), None),
        (Some(json!(0)), None),
        (Some(json!(1.5)), None),
        (Some(json!(99_999_999_999u64)), None),
        (Some(json!({"x": 1})), None),
        (Some(serde_json::Value::Null), None),
    ];
    for (raw, expected) in cases {
        let mut info = json!({
            "alias": "Peer", "version": "2.1", "fingerprint": "peer",
            "port": 53317, "protocol": "http"
        });
        if let Some(raw) = &raw {
            info["appBuild"] = raw.clone();
        }
        let response = client
            .post(&url)
            .json(&json!({
                "info": info,
                "files": {"f": {"id": "f", "fileName": "a.txt", "size": 1, "fileType": "text/plain"}}
            }))
            .send()
            .await
            .unwrap();
        // Declined by the test server: 403, never a 400 parse error.
        assert_eq!(response.status().as_u16(), 403, "appBuild = {raw:?}");
        let build = tokio::time::timeout(Duration::from_secs(5), server.sender_builds.recv())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(build, expected, "appBuild = {raw:?}");
    }
}
