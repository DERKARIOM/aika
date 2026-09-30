//! `GET /api/aika/v1/chat/ws`: upgrades an mTLS connection to a chat
//! WebSocket handed over to the [ChatHub].

use crate::chat::ws_config;
use crate::http::server::common::error::AppError;
use crate::http::server::common::response::{self, BoxedBody};
use crate::http::server::{AppState, RequestClientInfo};
use hyper::body::Incoming;
use hyper::header::{self, HeaderMap, HeaderValue};
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio_tungstenite::tungstenite::handshake::derive_accept_key;
use tokio_tungstenite::tungstenite::protocol::Role;
use tokio_tungstenite::WebSocketStream;

pub(crate) async fn upgrade(
    mut req: Request<Incoming>,
    state: AppState,
    client_info: RequestClientInfo,
) -> Result<Response<BoxedBody>, AppError> {
    // Not attached (chat disabled, or an app version without chat support
    // behind this server): the client falls back to the legacy transport.
    let Some(hub) = state.chat_hub() else {
        return Err(AppError::Status(StatusCode::NOT_FOUND));
    };

    // Without TLS there is no verified client certificate, hence no way to
    // know who is on the other end.
    let Some(fingerprint) = client_info.cert_fingerprint() else {
        return Err(AppError::Status(StatusCode::FORBIDDEN));
    };

    let Some(accept_key) = websocket_accept_key(req.headers()) else {
        return Err(AppError::Status(StatusCode::UPGRADE_REQUIRED));
    };

    if hub.check_capacity(&fingerprint).await.is_err() {
        return Err(AppError::Status(StatusCode::TOO_MANY_REQUESTS));
    }

    let on_upgrade = hyper::upgrade::on(&mut req);
    let ip = client_info.ip;
    let cancel = state.shutdown.clone();
    tokio::spawn(async move {
        let upgraded = match on_upgrade.await {
            Ok(upgraded) => upgraded,
            Err(err) => {
                tracing::warn!("Chat WebSocket upgrade from {ip} failed: {err:#}");
                return;
            }
        };
        let ws = WebSocketStream::from_raw_socket(
            TokioIo::new(upgraded),
            Role::Server,
            Some(ws_config()),
        )
        .await;
        if let Err(err) = hub.register(ws, fingerprint, ip, false, cancel).await {
            tracing::warn!("Chat connection from {ip} refused: {err}");
        }
    });

    let mut res = Response::new(response::empty_body());
    *res.status_mut() = StatusCode::SWITCHING_PROTOCOLS;
    let headers = res.headers_mut();
    headers.insert(header::UPGRADE, HeaderValue::from_static("websocket"));
    headers.insert(header::CONNECTION, HeaderValue::from_static("Upgrade"));
    headers.insert(
        header::SEC_WEBSOCKET_ACCEPT,
        HeaderValue::from_str(&accept_key)
            .map_err(|_| AppError::Status(StatusCode::BAD_REQUEST))?,
    );
    Ok(res)
}

/// Validates the WebSocket handshake headers (RFC 6455, section 4.2.1) and
/// returns the `Sec-WebSocket-Accept` value.
fn websocket_accept_key(headers: &HeaderMap) -> Option<String> {
    let has_token = |name: header::HeaderName, token: &str| {
        headers.get_all(name).iter().any(|value| {
            value
                .to_str()
                .map(|v| v.split(',').any(|t| t.trim().eq_ignore_ascii_case(token)))
                .unwrap_or(false)
        })
    };

    if !has_token(header::CONNECTION, "upgrade") || !has_token(header::UPGRADE, "websocket") {
        return None;
    }
    if headers.get(header::SEC_WEBSOCKET_VERSION)?.as_bytes() != b"13" {
        return None;
    }
    let key = headers.get(header::SEC_WEBSOCKET_KEY)?;
    Some(derive_accept_key(key.as_bytes()))
}
