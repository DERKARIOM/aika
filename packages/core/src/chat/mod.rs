//! Persistent, mutually authenticated WebSocket links used by the Aika chat.
//!
//! This module is transport only: it opens, authenticates and keeps alive
//! connections, and moves opaque text frames. The chat protocol itself
//! (hello, messages, acknowledgements) is implemented by the application.
//!
//! Every connection is bound to the SHA-256 fingerprint of the peer's TLS
//! certificate:
//! - inbound: the certificate the client presented during the mTLS handshake;
//! - outbound: the server certificate, which must match the fingerprint the
//!   caller expects (certificate pinning).

mod tls;

use futures_util::{SinkExt, StreamExt};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::{mpsc, Mutex};
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;
use tokio_util::sync::CancellationToken;

/// Path of the chat WebSocket endpoint.
pub const CHAT_WS_PATH: &str = "/api/aika/v1/chat/ws";

/// Largest accepted chat frame. Chat frames carry text and metadata only;
/// media still travels through the regular file-transfer endpoints.
pub const MAX_MESSAGE_SIZE: usize = 1024 * 1024;

/// A ping is sent after this much time without outgoing traffic.
const PING_INTERVAL: Duration = Duration::from_secs(15);

/// A connection is considered dead after this much time without any
/// incoming frame (a pong counts), so presence is detected within ~40 s.
const IDLE_TIMEOUT: Duration = Duration::from_secs(40);

const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);

/// Limits against a peer (or several) exhausting resources.
pub const MAX_CONNECTIONS_PER_PEER: usize = 4;
pub const MAX_CONNECTIONS: usize = 64;

const OUTGOING_QUEUE: usize = 64;
const EVENT_QUEUE: usize = 256;

pub(crate) fn ws_config() -> WebSocketConfig {
    WebSocketConfig::default()
        .max_message_size(Some(MAX_MESSAGE_SIZE))
        .max_frame_size(Some(MAX_MESSAGE_SIZE))
}

/// Events emitted by the hub, in order per connection:
/// one `Connected`, any number of `Message`, one `Disconnected`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChatHubEvent {
    Connected {
        connection_id: String,
        /// Verified SHA-256 fingerprint (uppercase hex) of the peer certificate.
        fingerprint: String,
        ip: IpAddr,
        /// `true` when this device initiated the connection.
        outbound: bool,
    },
    Message {
        connection_id: String,
        text: String,
    },
    Disconnected {
        connection_id: String,
        reason: String,
    },
}

#[derive(Debug, Error)]
pub enum ChatError {
    #[error("the peer presented a certificate with another fingerprint")]
    FingerprintMismatch,

    #[error("the peer does not support the chat WebSocket (HTTP {0})")]
    Unsupported(u16),

    #[error("too many chat connections")]
    TooManyConnections,

    #[error("unknown or closed chat connection")]
    NotConnected,

    #[error("chat frame larger than {MAX_MESSAGE_SIZE} bytes")]
    MessageTooLarge,

    #[error("timed out")]
    Timeout,

    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

struct ConnectionEntry {
    fingerprint: String,
    outgoing: mpsc::Sender<Message>,
}

struct HubInner {
    connections: Mutex<HashMap<String, ConnectionEntry>>,
    event_tx: mpsc::Sender<ChatHubEvent>,
    identity: tls::ClientIdentity,
    /// Cancelled by [ChatHub::shutdown]: closes every connection.
    shutdown: CancellationToken,
}

/// Owns every chat connection of this device, inbound and outbound.
#[derive(Clone)]
pub struct ChatHub {
    inner: Arc<HubInner>,
}

impl ChatHub {
    /// Creates a hub using this device's certificate and private key (PEM)
    /// as client identity for outbound connections.
    pub fn new(
        cert: &str,
        private_key: &str,
    ) -> anyhow::Result<(Self, mpsc::Receiver<ChatHubEvent>)> {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let (event_tx, event_rx) = mpsc::channel(EVENT_QUEUE);
        let hub = Self {
            inner: Arc::new(HubInner {
                connections: Mutex::new(HashMap::new()),
                event_tx,
                identity: tls::ClientIdentity::from_pem(cert, private_key)?,
                shutdown: CancellationToken::new(),
            }),
        };
        Ok((hub, event_rx))
    }

    /// Opens a chat connection to `ip:port`, accepting the peer only if its
    /// certificate fingerprint equals `expected_fingerprint`.
    /// Returns the connection ID (also announced by a `Connected` event).
    pub async fn connect(
        &self,
        ip: IpAddr,
        port: u16,
        expected_fingerprint: &str,
    ) -> Result<String, ChatError> {
        let fingerprint = expected_fingerprint.to_uppercase();
        self.check_capacity(&fingerprint).await?;

        let mismatch = Arc::new(AtomicBool::new(false));
        let connector = self
            .inner
            .identity
            .connector(&fingerprint, mismatch.clone())?;

        let connecting = async {
            let tcp = tokio::net::TcpStream::connect((ip, port))
                .await
                .map_err(anyhow::Error::from)?;
            let _ = tcp.set_nodelay(true);
            let server_name = rustls::pki_types::ServerName::IpAddress(ip.into());
            let tls = match connector.connect(server_name, tcp).await {
                Ok(tls) => tls,
                Err(_) if mismatch.load(Ordering::SeqCst) => {
                    return Err(ChatError::FingerprintMismatch);
                }
                Err(err) => return Err(ChatError::Other(err.into())),
            };

            let host = match ip {
                IpAddr::V4(v4) => v4.to_string(),
                IpAddr::V6(v6) => format!("[{v6}]"),
            };
            let request = format!("wss://{host}:{port}{CHAT_WS_PATH}")
                .into_client_request()
                .map_err(anyhow::Error::from)?;
            match tokio_tungstenite::client_async_with_config(request, tls, Some(ws_config())).await
            {
                Ok((ws, _)) => Ok(ws),
                Err(tokio_tungstenite::tungstenite::Error::Http(response)) => {
                    Err(ChatError::Unsupported(response.status().as_u16()))
                }
                Err(err) => Err(ChatError::Other(err.into())),
            }
        };

        let ws = tokio::time::timeout(CONNECT_TIMEOUT, connecting)
            .await
            .map_err(|_| ChatError::Timeout)??;

        self.register(ws, fingerprint, ip, true, self.inner.shutdown.clone())
            .await
    }

    /// Queues a text frame on a connection.
    pub async fn send(&self, connection_id: &str, text: String) -> Result<(), ChatError> {
        if text.len() > MAX_MESSAGE_SIZE {
            return Err(ChatError::MessageTooLarge);
        }
        let outgoing = {
            let connections = self.inner.connections.lock().await;
            let entry = connections
                .get(connection_id)
                .ok_or(ChatError::NotConnected)?;
            entry.outgoing.clone()
        };
        outgoing
            .send(Message::text(text))
            .await
            .map_err(|_| ChatError::NotConnected)
    }

    /// Closes a connection. Its `Disconnected` event follows.
    pub async fn close(&self, connection_id: &str) {
        // Dropping the only sender ends the connection task, which sends a
        // close frame.
        self.inner.connections.lock().await.remove(connection_id);
    }

    /// Closes every connection and refuses new ones.
    pub async fn shutdown(&self) {
        self.inner.shutdown.cancel();
        self.inner.connections.lock().await.clear();
    }

    /// Fingerprints of the currently connected peers, with their
    /// connection IDs.
    pub async fn connections(&self) -> Vec<(String, String)> {
        self.inner
            .connections
            .lock()
            .await
            .iter()
            .map(|(id, entry)| (id.clone(), entry.fingerprint.clone()))
            .collect()
    }

    pub(crate) async fn check_capacity(&self, fingerprint: &str) -> Result<(), ChatError> {
        if self.inner.shutdown.is_cancelled() {
            return Err(ChatError::NotConnected);
        }
        let connections = self.inner.connections.lock().await;
        let for_peer = connections
            .values()
            .filter(|c| c.fingerprint == fingerprint)
            .count();
        if connections.len() >= MAX_CONNECTIONS || for_peer >= MAX_CONNECTIONS_PER_PEER {
            return Err(ChatError::TooManyConnections);
        }
        Ok(())
    }

    /// Takes over an established WebSocket: announces it and runs it until
    /// it closes, the hub shuts down, or `cancel` fires (server stopped).
    pub(crate) async fn register<S>(
        &self,
        ws: WebSocketStream<S>,
        fingerprint: String,
        ip: IpAddr,
        outbound: bool,
        cancel: CancellationToken,
    ) -> Result<String, ChatError>
    where
        S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
    {
        let connection_id = uuid::Uuid::new_v4().to_string();
        let (outgoing_tx, outgoing_rx) = mpsc::channel(OUTGOING_QUEUE);
        {
            let mut connections = self.inner.connections.lock().await;
            connections.insert(
                connection_id.clone(),
                ConnectionEntry {
                    fingerprint: fingerprint.clone(),
                    outgoing: outgoing_tx,
                },
            );
            // Announced while holding the lock so that `Connected` always
            // precedes any `Message` of this connection.
            let _ = self
                .inner
                .event_tx
                .send(ChatHubEvent::Connected {
                    connection_id: connection_id.clone(),
                    fingerprint,
                    ip,
                    outbound,
                })
                .await;
        }

        let inner = self.inner.clone();
        let id = connection_id.clone();
        let shutdown = self.inner.shutdown.clone();
        tokio::spawn(async move {
            let reason = run_connection(&inner, &id, ws, outgoing_rx, cancel, shutdown).await;
            inner.connections.lock().await.remove(&id);
            tracing::debug!("Chat connection {id} closed: {reason}");
            let _ = inner
                .event_tx
                .send(ChatHubEvent::Disconnected {
                    connection_id: id,
                    reason,
                })
                .await;
        });

        Ok(connection_id)
    }
}

async fn run_connection<S>(
    inner: &HubInner,
    connection_id: &str,
    ws: WebSocketStream<S>,
    mut outgoing: mpsc::Receiver<Message>,
    cancel: CancellationToken,
    shutdown: CancellationToken,
) -> String
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let (mut sink, mut stream) = ws.split();
    let mut ping = tokio::time::interval_at(Instant::now() + PING_INTERVAL, PING_INTERVAL);
    let mut last_seen = Instant::now();

    let reason = loop {
        tokio::select! {
            _ = cancel.cancelled() => break "server stopped".to_string(),
            _ = shutdown.cancelled() => break "shutdown".to_string(),
            incoming = stream.next() => {
                last_seen = Instant::now();
                match incoming {
                    Some(Ok(Message::Text(text))) => {
                        let _ = inner.event_tx.send(ChatHubEvent::Message {
                            connection_id: connection_id.to_string(),
                            text: text.to_string(),
                        }).await;
                    }
                    Some(Ok(Message::Binary(_))) => break "binary frames are not supported".to_string(),
                    Some(Ok(Message::Ping(_) | Message::Pong(_) | Message::Frame(_))) => {}
                    Some(Ok(Message::Close(_))) | None => break "closed by peer".to_string(),
                    Some(Err(err)) => break format!("connection error: {err}"),
                }
            }
            message = outgoing.recv() => {
                match message {
                    Some(message) => {
                        if let Err(err) = sink.send(message).await {
                            break format!("send failed: {err}");
                        }
                    }
                    None => break "closed locally".to_string(),
                }
            }
            _ = ping.tick() => {
                if last_seen.elapsed() > IDLE_TIMEOUT {
                    break "timed out".to_string();
                }
                if let Err(err) = sink.send(Message::Ping(Default::default())).await {
                    break format!("send failed: {err}");
                }
            }
        }
    };

    let _ = tokio::time::timeout(Duration::from_secs(1), sink.close()).await;
    reason
}
