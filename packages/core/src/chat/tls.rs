//! TLS for outbound chat connections: mutual authentication with this
//! device's certificate, and pinning of the peer's certificate fingerprint.

use crate::crypto::cert::{fingerprint_from_cert_der, verify_cert_from_der};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls::pki_types::pem::PemObject;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, Error, SignatureScheme};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// This device's certificate chain and key, presented to the peer's server
/// (which requires a client certificate).
pub(super) struct ClientIdentity {
    certs: Vec<CertificateDer<'static>>,
    key: PrivateKeyDer<'static>,
}

impl ClientIdentity {
    pub(super) fn from_pem(cert: &str, private_key: &str) -> anyhow::Result<Self> {
        Ok(Self {
            certs: vec![CertificateDer::from_pem_slice(cert.as_bytes())?],
            key: PrivateKeyDer::from_pem_slice(private_key.as_bytes())?,
        })
    }

    /// A connector that only completes the handshake with a server whose
    /// certificate has `expected_fingerprint`. `mismatch` is set when the
    /// handshake failed for that reason.
    pub(super) fn connector(
        &self,
        expected_fingerprint: &str,
        mismatch: Arc<AtomicBool>,
    ) -> anyhow::Result<tokio_rustls::TlsConnector> {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let verifier = PinnedServerCertVerifier {
            expected_fingerprint: expected_fingerprint.to_uppercase(),
            mismatch,
            provider: provider.clone(),
        };
        let config = rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()?
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(verifier))
            .with_client_auth_cert(self.certs.clone(), self.key.clone_key())?;
        Ok(tokio_rustls::TlsConnector::from(Arc::new(config)))
    }
}

/// Aika devices use self-signed certificates, so there is no authority to
/// check against. The identity of a peer *is* its certificate fingerprint,
/// already known from discovery (and trusted by the user through the chat
/// contact list), so the connection is accepted only for that exact
/// certificate, which must also be well-formed and currently valid.
#[derive(Debug)]
struct PinnedServerCertVerifier {
    expected_fingerprint: String,
    mismatch: Arc<AtomicBool>,
    provider: Arc<CryptoProvider>,
}

impl ServerCertVerifier for PinnedServerCertVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        if fingerprint_from_cert_der(end_entity) != self.expected_fingerprint {
            self.mismatch.store(true, Ordering::SeqCst);
            return Err(Error::InvalidCertificate(
                rustls::CertificateError::ApplicationVerificationFailure,
            ));
        }
        verify_cert_from_der(end_entity, None).map_err(|err| {
            tracing::warn!("Chat peer certificate rejected: {err:#}");
            Error::InvalidCertificate(rustls::CertificateError::BadEncoding)
        })?;
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        verify_tls12_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.provider
            .signature_verification_algorithms
            .supported_schemes()
    }
}
