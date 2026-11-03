use crate::model::transfer::FileDto;
use std::collections::HashMap;
use std::net::IpAddr;
use tokio::time::{Duration, Instant};

/// An accepted session with no file being received for this long has been
/// abandoned by its sender (it vanished mid-transfer: Wi-Fi lost, device
/// asleep, app killed without cancelling). Senders upload right after the
/// session is accepted and back to back, so a live session is never idle
/// for that long between two files.
pub(crate) const ABANDONED_SESSION_AFTER: Duration = Duration::from_secs(60);

/// State of the single v2 upload session slot.
pub(crate) enum SessionStateV2 {
    /// A prepare-upload request is waiting for the application's decision.
    Pending,

    /// An accepted upload session.
    Active(UploadSessionV2),
}

pub(crate) struct UploadSessionV2 {
    pub(crate) session_id: String,

    /// The IP address of the sender. Uploads are only accepted from this address.
    pub(crate) sender_ip: IpAddr,

    /// The accepted files, mapped by file ID.
    pub(crate) files: HashMap<String, SessionFileV2>,

    /// Last time the session made progress (created, a file started or ended).
    pub(crate) last_activity: Instant,
}

impl UploadSessionV2 {
    /// Whether all files reached a final state.
    pub(crate) fn is_complete(&self) -> bool {
        self.files
            .values()
            .all(|file| matches!(file.status, FileStatusV2::Finished | FileStatusV2::Failed))
    }

    /// Whether the sender gave up on this session without cancelling it:
    /// no file is being received and nothing happened for
    /// [ABANDONED_SESSION_AFTER]. Such a session would otherwise block
    /// every new transfer ("Blocked by another session") until a restart.
    pub(crate) fn is_abandoned(&self, now: Instant) -> bool {
        let receiving = self
            .files
            .values()
            .any(|file| file.status == FileStatusV2::InProgress);
        !receiving && now.saturating_duration_since(self.last_activity) >= ABANDONED_SESSION_AFTER
    }

    /// Records progress of the session.
    pub(crate) fn touch(&mut self) {
        self.last_activity = Instant::now();
    }
}

pub(crate) struct SessionFileV2 {
    pub(crate) dto: FileDto,

    /// The file-specific token required for the upload request.
    pub(crate) token: String,

    pub(crate) status: FileStatusV2,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum FileStatusV2 {
    Pending,
    InProgress,
    Finished,
    Failed,
}
