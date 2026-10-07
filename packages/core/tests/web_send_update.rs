#![cfg(feature = "http")]

//! The host adds or removes shared files while the web share link is open.

use bytes::Bytes;
use localsend::http::server::v2::ServerEventV2;
use localsend::http::server::web::{WebSendConfig, WebSendEvent, WebSendI18n};
use localsend::http::server::{start_with_port, ServerConfigV2};
use localsend::http::state::ClientInfo;
use localsend::model::transfer::{FileContent, FileDto};
use localsend::reqwest;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

fn file_dto(id: &str, name: &str, size: u64) -> FileDto {
    FileDto {
        id: id.to_string(),
        file_name: name.to_string(),
        size,
        file_type: "text/plain".to_string(),
        sha256: None,
        preview: None,
        metadata: None,
    }
}

#[tokio::test]
async fn test_set_web_send_files_while_running() {
    let _ = tracing_subscriber::fmt().with_test_writer().try_init();
    let port = 43551;
    let prepare_events = Arc::new(AtomicU32::new(0));

    let (web_tx, mut web_rx) = mpsc::channel::<WebSendEvent>(16);
    tokio::spawn({
        let prepare_events = prepare_events.clone();
        async move {
            while let Some(event) = web_rx.recv().await {
                match event {
                    WebSendEvent::PrepareDownload { decision_tx, .. } => {
                        prepare_events.fetch_add(1, Ordering::SeqCst);
                        let _ = decision_tx.send(true);
                    }
                    WebSendEvent::FileDownload {
                        file, content_tx, ..
                    } => {
                        let (tx, rx) = mpsc::channel(4);
                        let _ = content_tx.send(FileContent::Stream(rx));
                        let _ = tx.send(Bytes::from(file.file_name.into_bytes())).await;
                    }
                }
            }
        }
    });
    let (v2_tx, _v2_rx) = mpsc::channel::<ServerEventV2>(16);
    let (_stop_tx, stop_rx) = oneshot::channel();

    // Starts without any file: a "receive only" link.
    let handle = start_with_port(
        port,
        None,
        ClientInfo {
            alias: "Host".to_string(),
            version: "2.1".to_string(),
            device_model: None,
            device_type: None,
            token: "fp".to_string(),
        },
        None,
        Some(ServerConfigV2 {
            pin: None,
            event_tx: v2_tx,
        }),
        Some(WebSendConfig {
            files: HashMap::new(),
            pin: None,
            i18n: WebSendI18n::default(),
            event_tx: web_tx,
        }),
        stop_rx,
    )
    .await
    .unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;

    let base = format!("http://127.0.0.1:{port}/api/localsend/v2");
    let client = reqwest::Client::new();

    let body: Value = client
        .post(format!("{base}/prepare-download"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let session = body["sessionId"].as_str().unwrap().to_string();
    assert_eq!(body["files"].as_object().unwrap().len(), 0);

    // Unknown session: refused, and never turned into a new request to the host.
    let res = client
        .get(format!("{base}/web/files?sessionId=forged"))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status().as_u16(), 403);
    assert_eq!(prepare_events.load(Ordering::SeqCst), 1);

    // The host adds a file: the accepted session sees it and can download it.
    assert!(handle.set_web_send_files(HashMap::from([(
        "a".to_string(),
        file_dto("a", "hello.txt", 9)
    )])));
    let body: Value = client
        .get(format!("{base}/web/files?sessionId={session}"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(body["files"]["a"]["fileName"], "hello.txt");
    let content = client
        .get(format!("{base}/download?sessionId={session}&fileId=a"))
        .send()
        .await
        .unwrap()
        .bytes()
        .await
        .unwrap();
    assert_eq!(&content[..], b"hello.txt");

    // The host removes it again: no longer downloadable.
    assert!(handle.set_web_send_files(HashMap::new()));
    let res = client
        .get(format!("{base}/download?sessionId={session}&fileId=a"))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status().as_u16(), 403);

    // No new prepare-download request was needed at any point.
    assert_eq!(prepare_events.load(Ordering::SeqCst), 1);
}
