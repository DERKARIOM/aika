/// Status of the Google Play In-App Update flow.
enum UpdateStatus {
  /// Nothing has happened yet, or an update finished installing.
  idle,

  /// A check is running against the Play In-App Update API.
  checking,

  /// The last check completed and this build is up to date.
  notAvailable,

  /// An optional update is available (flexible flow proposed, or dismissed).
  available,

  /// A flexible update is downloading in the background.
  downloading,

  /// A flexible update is downloaded and waits for `completeFlexibleUpdate()`.
  readyToInstall,

  /// Google Play's immediate (blocking) update screen is open or resuming.
  immediateInProgress,

  /// A mandatory update is applicable but was not installed (the user left
  /// Google Play's screen): Aika shows its blocking screen until it is.
  updateRequired,

  /// The last check or update attempt failed (offline, Play error...). Not
  /// surfaced for automatic checks: Aika keeps working on this version.
  failed,

  /// In-App Updates are not usable here: not Android, not installed from
  /// Google Play, or no Play Store / Play Services.
  unsupported,
}

/// Immutable state of update_provider.dart. Hand-written (no dart_mappable)
/// to keep the Play-only feature free of generated code.
class UpdateState {
  final UpdateStatus status;

  /// versionCode of the installed build, from the platform package info.
  final int? installedVersionCode;

  /// versionCode Google Play offers, when an update is available.
  final int? availableVersionCode;

  /// Update priority (0-5) Google Play reports for the available release.
  final int? updatePriority;

  /// Whether Play allows an immediate (blocking) update right now.
  final bool immediateAllowed;

  /// Whether Play allows a flexible (background) update right now.
  final bool flexibleAllowed;

  /// Technical detail of the last failure, for logs and debugging only.
  final String? errorMessage;

  const UpdateState({
    required this.status,
    this.installedVersionCode,
    this.availableVersionCode,
    this.updatePriority,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.errorMessage,
  });

  factory UpdateState.initial() => const UpdateState(status: UpdateStatus.idle);

  /// A mandatory update is pending or being installed.
  bool get mandatoryPending => status == UpdateStatus.updateRequired || status == UpdateStatus.immediateInProgress;

  /// [errorMessage] only describes the step that produced this state: it is
  /// cleared unless given again.
  UpdateState copyWith({
    UpdateStatus? status,
    int? installedVersionCode,
    int? availableVersionCode,
    int? updatePriority,
    bool? immediateAllowed,
    bool? flexibleAllowed,
    String? errorMessage,
  }) {
    return UpdateState(
      status: status ?? this.status,
      installedVersionCode: installedVersionCode ?? this.installedVersionCode,
      availableVersionCode: availableVersionCode ?? this.availableVersionCode,
      updatePriority: updatePriority ?? this.updatePriority,
      immediateAllowed: immediateAllowed ?? this.immediateAllowed,
      flexibleAllowed: flexibleAllowed ?? this.flexibleAllowed,
      errorMessage: errorMessage,
    );
  }
}
