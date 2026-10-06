use bytes::Bytes;
use http_body_util::BodyExt;
use hyper::body::Incoming;
use hyper::Request;
use std::future::Future;
use std::path::PathBuf;
use tokio::sync::{mpsc, oneshot};

/// Channel capacity for file upload chunks (provides backpressure).
const UPLOAD_CHANNEL_CAPACITY: usize = 16;

/// Why an upload could not be saved, as far as the HTTP response is concerned.
///
/// Only the classification is exposed to the remote client; the detailed
/// message (which may contain local paths) stays in the logs and in the
/// `result_tx` channel of the application.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SaveFailure {
    /// The destination has no space left (or the user quota is exceeded).
    StorageFull,

    /// The file exceeds the maximum file size of the destination
    /// (e.g. 4 GiB on FAT32).
    FileTooLarge,

    /// Any other failure: I/O error, interrupted or truncated transfer,
    /// cancelled by the application...
    Other,
}

impl SaveFailure {
    /// Classifies an I/O error raised while creating or writing the file.
    fn from_io(err: &std::io::Error) -> Self {
        use std::io::ErrorKind;
        match err.kind() {
            ErrorKind::StorageFull | ErrorKind::QuotaExceeded => SaveFailure::StorageFull,
            ErrorKind::FileTooLarge => SaveFailure::FileTooLarge,
            _ => SaveFailure::Other,
        }
    }
}

/// A failed write: the classification plus a detailed message.
struct WriteError {
    failure: SaveFailure,
    message: String,
}

impl WriteError {
    fn other(message: String) -> Self {
        Self {
            failure: SaveFailure::Other,
            message,
        }
    }

    fn io(context: &str, err: std::io::Error) -> Self {
        Self {
            failure: SaveFailure::from_io(&err),
            message: format!("{context}: {err}"),
        }
    }
}

/// Where the content of an uploaded file should go, decided by the application.
#[derive(Debug)]
pub enum FileUploadTarget {
    /// The application consumes the binary chunks itself.
    ///
    /// The server forwards chunks into `binary_tx` and closes it at end of file.
    /// The application should compare the number of received bytes with `file.size`
    /// and report the result on the sender side of `result_rx` which determines
    /// the HTTP response (200 on `Ok`, 500 on `Err` or when the sender is dropped).
    Stream {
        /// Channel the server sends the binary chunks of the file into.
        binary_tx: mpsc::Sender<Bytes>,

        /// Channel on which the application reports whether the file was
        /// processed successfully.
        result_rx: oneshot::Receiver<Result<(), String>>,
    },

    /// The server writes the file to this path (created or truncated)
    /// and reports the result on `result_tx`.
    Path {
        /// The path to write the file to.
        path: PathBuf,

        /// Channel on which the server reports whether the file was saved successfully.
        result_tx: oneshot::Sender<Result<(), String>>,

        /// Optional channel on which the server reports the number of bytes
        /// written so far. Events are dropped when the channel is full.
        progress_tx: Option<mpsc::Sender<u64>>,
    },

    /// The server writes the file to this raw file descriptor (Android only)
    /// and reports the result on `result_tx`.
    #[cfg(target_os = "android")]
    Fd {
        /// The raw file descriptor to write the file to.
        /// Ownership is transferred; the descriptor is closed after writing.
        fd: std::os::fd::RawFd,

        /// Channel on which the server reports whether the file was saved successfully.
        result_tx: oneshot::Sender<Result<(), String>>,

        /// Optional channel on which the server reports the number of bytes
        /// written so far. Events are dropped when the channel is full.
        progress_tx: Option<mpsc::Sender<u64>>,
    },
}

/// Forwards the request body to `target`.
///
/// Returns `Ok(())` once the file was fully saved, or the reason why it was not.
pub(crate) async fn save_req_to_target(
    req: Request<Incoming>,
    target: FileUploadTarget,
    file_size: u64,
) -> Result<(), SaveFailure> {
    // Resolve the target into a chunk sender and a result receiver.
    let (binary_tx, result_rx) = match target {
        FileUploadTarget::Stream {
            binary_tx,
            result_rx,
        } => {
            // The application reports a plain message: no classification possible.
            let (classified_tx, classified_rx) = oneshot::channel();
            tokio::spawn(async move {
                let result = match result_rx.await {
                    Ok(Ok(())) => Ok(()),
                    Ok(Err(message)) => Err(WriteError::other(message)),
                    Err(_) => Err(WriteError::other("Result channel dropped".to_string())),
                };
                let _ = classified_tx.send(result);
            });
            (binary_tx, classified_rx)
        }
        FileUploadTarget::Path {
            path,
            result_tx,
            progress_tx,
        } => spawn_file_writer(
            async move {
                tokio::fs::File::create(&path)
                    .await
                    .map_err(|e| WriteError::io(&format!("Failed to create {}", path.display()), e))
            },
            file_size,
            result_tx,
            progress_tx,
        ),
        #[cfg(target_os = "android")]
        FileUploadTarget::Fd {
            fd,
            result_tx,
            progress_tx,
        } => spawn_file_writer(
            async move {
                use std::os::fd::FromRawFd;

                // SAFETY: the descriptor is owned by this transfer; wrapping it in
                // a File transfers that ownership so it is closed once writing finishes.
                let std_file = unsafe { std::fs::File::from_raw_fd(fd) };
                Ok(tokio::fs::File::from_std(std_file))
            },
            file_size,
            result_tx,
            progress_tx,
        ),
    };

    // Forward the request body to the target.
    let mut body = req.into_body();
    let mut stream_error = false;
    while let Some(frame) = body.frame().await {
        match frame {
            Ok(frame) => {
                let Ok(data) = frame.into_data() else {
                    continue; // ignore non-data frames (e.g. trailers)
                };
                if data.is_empty() {
                    continue;
                }
                if binary_tx.send(data).await.is_err() {
                    // The receiver is gone (dropped by the application or
                    // closed by the file writer after an error).
                    stream_error = true;
                    break;
                }
            }
            Err(err) => {
                tracing::warn!("Error reading upload body of file: {err:#}");
                stream_error = true;
                break;
            }
        }
    }

    // Signal end of file to the receiving side.
    drop(binary_tx);

    // The writer result is awaited even after a body error: when the writer
    // failed first (e.g. disk full), it closed the channel which surfaces here
    // as a send error, and its classification is the one that matters.
    let result = match stream_error {
        // Bounded wait: the writer reports promptly once the channel is closed,
        // but an application-provided stream must never hang the request.
        true => tokio::time::timeout(std::time::Duration::from_secs(5), result_rx)
            .await
            .unwrap_or_else(|_| Ok(Err(WriteError::other("Timed out".to_string())))),
        false => result_rx.await,
    };
    match result {
        Ok(Ok(())) if !stream_error => Ok(()),
        Ok(Ok(())) => Err(SaveFailure::Other),
        Ok(Err(err)) => {
            tracing::warn!("Failed to process file: {}", err.message);
            Err(err.failure)
        }
        Err(_) => Err(SaveFailure::Other),
    }
}

/// Spawns a task that writes incoming chunks to a file provided by `open`.
///
/// Returns the sender for the binary chunks and a receiver for the final result.
/// The result is additionally reported to the application on `result_tx`.
fn spawn_file_writer(
    open: impl Future<Output = Result<tokio::fs::File, WriteError>> + Send + 'static,
    expected_size: u64,
    result_tx: oneshot::Sender<Result<(), String>>,
    progress_tx: Option<mpsc::Sender<u64>>,
) -> (
    mpsc::Sender<Bytes>,
    oneshot::Receiver<Result<(), WriteError>>,
) {
    let (binary_tx, mut binary_rx) = mpsc::channel::<Bytes>(UPLOAD_CHANNEL_CAPACITY);
    let (internal_tx, internal_rx) = oneshot::channel::<Result<(), WriteError>>();

    tokio::spawn(async move {
        let result =
            write_file_from_receiver(open, expected_size, &mut binary_rx, progress_tx).await;
        // Unblock the request handler if it is still sending chunks.
        binary_rx.close();
        let _ = result_tx.send(result.as_ref().map(|_| ()).map_err(|e| e.message.clone()));
        let _ = internal_tx.send(result);
    });

    (binary_tx, internal_rx)
}

/// Writes all chunks received on `rx` to the file provided by `open`.
///
/// Fails if the total number of written bytes does not match `expected_size`
/// (e.g. the sender disconnected mid-transfer).
async fn write_file_from_receiver(
    open: impl Future<Output = Result<tokio::fs::File, WriteError>>,
    expected_size: u64,
    rx: &mut mpsc::Receiver<Bytes>,
    progress_tx: Option<mpsc::Sender<u64>>,
) -> Result<(), WriteError> {
    use tokio::io::AsyncWriteExt;

    let mut file = open.await?;
    let mut written: u64 = 0;
    while let Some(chunk) = rx.recv().await {
        written += chunk.len() as u64;
        if written > expected_size {
            return Err(WriteError::other(format!(
                "Expected {expected_size} bytes, received at least {written}"
            )));
        }
        file.write_all(&chunk)
            .await
            .map_err(|e| WriteError::io("Failed to write file", e))?;
        if let Some(progress_tx) = &progress_tx {
            // Progress is best-effort: drop the event when the consumer lags.
            let _ = progress_tx.try_send(written);
        }
    }
    file.flush()
        .await
        .map_err(|e| WriteError::io("Failed to flush file", e))?;

    if written != expected_size {
        return Err(WriteError::other(format!(
            "Expected {expected_size} bytes, received {written}"
        )));
    }
    Ok(())
}
