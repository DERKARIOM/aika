use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use localsend::chat::{ChatError, ChatHub, ChatHubEvent};
use std::net::IpAddr;
use tokio::sync::{Mutex, mpsc};

/// Events of the chat hub, in order per connection:
/// one `Connected`, any number of `Message`, one `Disconnected`.
pub enum RsChatEvent {
    Connected {
        connection_id: String,
        /// Verified SHA-256 fingerprint (uppercase hex) of the peer certificate.
        fingerprint: String,
        ip: String,
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

pub enum RsChatError {
    /// The peer presented a certificate with another fingerprint:
    /// possibly another device impersonating it.
    FingerprintMismatch,
    /// The peer has no chat WebSocket (e.g. v1.0.3, HTTP 404) or refused it.
    Unsupported {
        status: u16,
    },
    TooManyConnections,
    NotConnected,
    MessageTooLarge,
    Timeout,
    Other {
        message: String,
    },
}

impl From<ChatError> for RsChatError {
    fn from(err: ChatError) -> Self {
        match err {
            ChatError::FingerprintMismatch => RsChatError::FingerprintMismatch,
            ChatError::Unsupported(status) => RsChatError::Unsupported { status },
            ChatError::TooManyConnections => RsChatError::TooManyConnections,
            ChatError::NotConnected => RsChatError::NotConnected,
            ChatError::MessageTooLarge => RsChatError::MessageTooLarge,
            ChatError::Timeout => RsChatError::Timeout,
            ChatError::Other(err) => RsChatError::Other {
                message: format!("{err:#}"),
            },
        }
    }
}

/// Owns every chat WebSocket connection of this device, inbound (accepted
/// by the HTTP server once attached with [crate::api::server::RsHttpServer::attach_chat_hub])
/// and outbound ([RsChatHub::connect]).
pub struct RsChatHub {
    pub(crate) inner: ChatHub,
    event_rx: Mutex<Option<mpsc::Receiver<ChatHubEvent>>>,
}

/// Creates the chat hub with this device's certificate and private key (PEM),
/// the same as the HTTP server's TLS identity.
#[frb(sync)]
pub fn create_chat_hub(cert: String, private_key: String) -> anyhow::Result<RsChatHub> {
    let (inner, event_rx) = ChatHub::new(&cert, &private_key)?;
    Ok(RsChatHub {
        inner,
        event_rx: Mutex::new(Some(event_rx)),
    })
}

impl RsChatHub {
    /// Emits the chat events. Can only be listened to once.
    pub async fn listen(&self, sink: StreamSink<RsChatEvent>) {
        let Some(mut event_rx) = self.event_rx.lock().await.take() else {
            let _ = sink.add_error(anyhow::anyhow!("Chat events already listened to"));
            return;
        };
        while let Some(event) = event_rx.recv().await {
            let event = match event {
                ChatHubEvent::Connected {
                    connection_id,
                    fingerprint,
                    ip,
                    outbound,
                } => RsChatEvent::Connected {
                    connection_id,
                    fingerprint,
                    ip: ip.to_string(),
                    outbound,
                },
                ChatHubEvent::Message {
                    connection_id,
                    text,
                } => RsChatEvent::Message {
                    connection_id,
                    text,
                },
                ChatHubEvent::Disconnected {
                    connection_id,
                    reason,
                } => RsChatEvent::Disconnected {
                    connection_id,
                    reason,
                },
            };
            if sink.add(event).is_err() {
                break;
            }
        }
    }

    /// Opens a chat connection, accepted only if the peer's certificate has
    /// [fingerprint]. Returns the connection ID.
    pub async fn connect(
        &self,
        ip: String,
        port: u16,
        fingerprint: String,
    ) -> Result<String, RsChatError> {
        let ip: IpAddr = ip.parse().map_err(|_| RsChatError::Other {
            message: format!("Invalid IP address: {ip}"),
        })?;
        Ok(self.inner.connect(ip, port, &fingerprint).await?)
    }

    /// Queues a text frame on a connection.
    pub async fn send(&self, connection_id: String, text: String) -> Result<(), RsChatError> {
        Ok(self.inner.send(&connection_id, text).await?)
    }

    /// Closes a connection; a `Disconnected` event follows.
    pub async fn close(&self, connection_id: String) {
        self.inner.close(&connection_id).await;
    }

    /// Closes every connection and refuses new ones.
    pub async fn shutdown(&self) {
        self.inner.shutdown().await;
    }
}
