#![cfg(feature = "http")]

use localsend::chat::{
    ChatError, ChatHub, ChatHubEvent, CHAT_WS_PATH, MAX_CONNECTIONS_PER_PEER, MAX_MESSAGE_SIZE,
};
use localsend::crypto::cert::fingerprint_from_cert_der;
use localsend::http::server::{start_with_port, ServerHandle, TlsConfig};
use localsend::http::state::ClientInfo;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::atomic::{AtomicU16, Ordering};
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

const LOCALHOST: IpAddr = IpAddr::V4(Ipv4Addr::LOCALHOST);

/// A device identity: self-signed certificate like the app generates.
struct Identity {
    cert: String,
    key: String,
    fingerprint: String,
}

fn identity(name: &str) -> Identity {
    let key = rcgen::KeyPair::generate().unwrap();
    let params = rcgen::CertificateParams::new(vec![name.to_string()]).unwrap();
    let cert = params.self_signed(&key).unwrap();
    Identity {
        fingerprint: fingerprint_from_cert_der(cert.der()),
        cert: cert.pem(),
        key: key.serialize_pem(),
    }
}

struct Device {
    identity: Identity,
    hub: ChatHub,
    events: mpsc::Receiver<ChatHubEvent>,
}

impl Device {
    fn new(name: &str) -> Self {
        let identity = identity(name);
        let (hub, events) = ChatHub::new(&identity.cert, &identity.key).unwrap();
        Self {
            identity,
            hub,
            events,
        }
    }

    async fn next_event(&mut self) -> ChatHubEvent {
        tokio::time::timeout(Duration::from_secs(5), self.events.recv())
            .await
            .expect("no chat event within 5 s")
            .expect("event channel closed")
    }
}

struct Server {
    port: u16,
    handle: ServerHandle,
    stop_tx: Option<oneshot::Sender<()>>,
}

impl Server {
    async fn stop(&mut self) {
        if let Some(stop_tx) = self.stop_tx.take() {
            let _ = stop_tx.send(());
            self.handle.wait_stopped().await;
        }
    }
}

/// Starts the server of `device`, with its chat hub attached when `attach`.
async fn start_server(device: &Device, tls: bool, attach: bool) -> Server {
    let _ = tracing_subscriber::fmt().with_test_writer().try_init();
    let port = free_port();
    let (stop_tx, stop_rx) = oneshot::channel();
    let handle = start_with_port(
        port,
        tls.then(|| TlsConfig {
            cert: device.identity.cert.clone(),
            private_key: device.identity.key.clone(),
        }),
        ClientInfo {
            alias: "server".to_string(),
            version: "2.1".to_string(),
            device_model: None,
            device_type: None,
            token: device.identity.fingerprint.clone(),
        },
        None,
        None,
        None,
        stop_rx,
    )
    .await
    .unwrap();
    if attach {
        handle.attach_chat_hub(Some(device.hub.clone()));
    }
    wait_until_reachable(port).await;
    Server {
        port,
        handle,
        stop_tx: Some(stop_tx),
    }
}

fn free_port() -> u16 {
    static PORT_COUNTER: AtomicU16 = AtomicU16::new(47551);
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

fn connected(event: ChatHubEvent) -> (String, String, bool) {
    match event {
        ChatHubEvent::Connected {
            connection_id,
            fingerprint,
            outbound,
            ..
        } => (connection_id, fingerprint, outbound),
        other => panic!("expected Connected, got {other:?}"),
    }
}

#[tokio::test]
async fn test_exchange_messages_both_ways() {
    let mut alice = Device::new("alice");
    let mut bob = Device::new("bob");
    let _server = start_server(&bob, true, true).await;

    let id_at_alice = alice
        .hub
        .connect(LOCALHOST, _server.port, &bob.identity.fingerprint)
        .await
        .unwrap();

    // Each side learns the other's verified fingerprint.
    let (id, fingerprint, outbound) = connected(alice.next_event().await);
    assert_eq!(
        (id.as_str(), fingerprint.as_str(), outbound),
        (
            id_at_alice.as_str(),
            bob.identity.fingerprint.as_str(),
            true
        )
    );
    let (id_at_bob, fingerprint, outbound) = connected(bob.next_event().await);
    assert_eq!(
        (fingerprint.as_str(), outbound),
        (alice.identity.fingerprint.as_str(), false)
    );

    alice
        .hub
        .send(&id_at_alice, "salut Bob".to_string())
        .await
        .unwrap();
    assert_eq!(
        bob.next_event().await,
        ChatHubEvent::Message {
            connection_id: id_at_bob.clone(),
            text: "salut Bob".to_string()
        }
    );

    bob.hub
        .send(&id_at_bob, "salut Alice 👋".to_string())
        .await
        .unwrap();
    assert_eq!(
        alice.next_event().await,
        ChatHubEvent::Message {
            connection_id: id_at_alice.clone(),
            text: "salut Alice 👋".to_string()
        }
    );

    alice.hub.close(&id_at_alice).await;
    assert!(
        matches!(alice.next_event().await, ChatHubEvent::Disconnected { connection_id, .. } if connection_id == id_at_alice)
    );
    assert!(
        matches!(bob.next_event().await, ChatHubEvent::Disconnected { connection_id, .. } if connection_id == id_at_bob)
    );
    assert!(matches!(
        bob.hub.send(&id_at_bob, "trop tard".to_string()).await,
        Err(ChatError::NotConnected)
    ));
}

#[tokio::test]
async fn test_rejects_a_server_with_another_fingerprint() {
    let alice = Device::new("alice");
    let mut bob = Device::new("bob");
    let mallory = Device::new("mallory");
    // Mallory answers where Alice expects Bob.
    let server = start_server(&mallory, true, true).await;

    let result = alice
        .hub
        .connect(LOCALHOST, server.port, &bob.identity.fingerprint)
        .await;

    assert!(
        matches!(result, Err(ChatError::FingerprintMismatch)),
        "{result:?}"
    );
    assert!(alice.hub.connections().await.is_empty());
    assert!(
        tokio::time::timeout(Duration::from_millis(300), bob.events.recv())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn test_fingerprint_comparison_ignores_case() {
    let alice = Device::new("alice");
    let bob = Device::new("bob");
    let server = start_server(&bob, true, true).await;

    let result = alice
        .hub
        .connect(
            LOCALHOST,
            server.port,
            &bob.identity.fingerprint.to_lowercase(),
        )
        .await;

    assert!(result.is_ok(), "{result:?}");
}

#[tokio::test]
async fn test_route_absent_without_attached_hub() {
    let alice = Device::new("alice");
    let bob = Device::new("bob");
    let server = start_server(&bob, true, false).await;

    let result = alice
        .hub
        .connect(LOCALHOST, server.port, &bob.identity.fingerprint)
        .await;

    // What a v1.0.3 peer answers too: the app falls back to the legacy envelope.
    assert!(
        matches!(result, Err(ChatError::Unsupported(404))),
        "{result:?}"
    );
}

#[tokio::test]
async fn test_refused_without_tls() {
    let bob = Device::new("bob");
    let server = start_server(&bob, false, true).await;

    let response = localsend::reqwest::Client::new()
        .get(format!("http://127.0.0.1:{}{CHAT_WS_PATH}", server.port))
        .header("Connection", "Upgrade")
        .header("Upgrade", "websocket")
        .header("Sec-WebSocket-Version", "13")
        .header("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
        .send()
        .await
        .unwrap();

    assert_eq!(response.status().as_u16(), 403);
}

#[tokio::test]
async fn test_server_stop_disconnects_peers() {
    let mut alice = Device::new("alice");
    let mut bob = Device::new("bob");
    let mut server = start_server(&bob, true, true).await;

    let id = alice
        .hub
        .connect(LOCALHOST, server.port, &bob.identity.fingerprint)
        .await
        .unwrap();
    connected(alice.next_event().await);
    connected(bob.next_event().await);

    server.stop().await;

    assert!(
        matches!(bob.next_event().await, ChatHubEvent::Disconnected { reason, .. } if reason == "server stopped")
    );
    assert!(
        matches!(alice.next_event().await, ChatHubEvent::Disconnected { connection_id, .. } if connection_id == id)
    );
}

#[tokio::test]
async fn test_limits() {
    let alice = Device::new("alice");
    let bob = Device::new("bob");
    let server = start_server(&bob, true, true).await;

    let mut ids = Vec::new();
    for _ in 0..MAX_CONNECTIONS_PER_PEER {
        ids.push(
            alice
                .hub
                .connect(LOCALHOST, server.port, &bob.identity.fingerprint)
                .await
                .unwrap(),
        );
    }
    assert!(matches!(
        alice
            .hub
            .connect(LOCALHOST, server.port, &bob.identity.fingerprint)
            .await,
        Err(ChatError::TooManyConnections)
    ));

    assert!(matches!(
        alice
            .hub
            .send(&ids[0], "x".repeat(MAX_MESSAGE_SIZE + 1))
            .await,
        Err(ChatError::MessageTooLarge)
    ));
}
