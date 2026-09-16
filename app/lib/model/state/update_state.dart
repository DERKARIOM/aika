/// Status of the Google Play In-App Update flow. Kept as a plain enum
/// (rather than a sealed class) since update_provider.dart already carries
/// the extra fields (priority, allowed flags, error message) alongside it.
enum UpdateStatus {
  /// Nothing has happened yet, or a flexible update just finished
  /// installing (completeFlexibleUpdate ran).
  idle,

  /// A check is currently running against the Play In-App Update API.
  checking,

  /// The last check completed and no update is available.
  notAvailable,

  /// An update is available on Google Play but the user hasn't started it
  /// yet (or has dismissed the dialog for a flexible update).
  available,

  /// A flexible update is being downloaded in the background.
  downloading,

  /// A flexible update finished downloading and is waiting for the user to
  /// trigger `completeFlexibleUpdate()` (app restart) to actually install.
  readyToInstall,

  /// The last check or update attempt failed (network error, Play Services
  /// unavailable, user cancelled an immediate update, etc). This is not
  /// surfaced as an error to the user for background checks -- Aika simply
  /// keeps working with the current version.
  failed,

  /// In-App Updates are not usable in this context: not Android, the app
  /// wasn't installed via Google Play, or Play Services isn't available.
  unsupported,
}

/// Hand-written, plain, immutable state class for update_provider.dart.
///
/// Deliberately NOT using `@MappableClass()` / dart_mappable (unlike most
/// other state classes in this codebase, e.g. PurchaseState): dart_mappable
/// requires a generated `*.mapper.dart` part file produced by build_runner,
/// and this class is written in an environment without a Dart/Flutter
/// toolchain to run codegen. A manual `copyWith` is used instead.
class UpdateState {
  final UpdateStatus status;

  /// Update priority (0-5) as configured in the Google Play Console for the
  /// available release. Null until a successful check reports an update.
  final int? updatePriority;

  /// Whether Play reports that an immediate (blocking) update is allowed
  /// for the current device/install state.
  final bool immediateAllowed;

  /// Whether Play reports that a flexible (background) update is allowed
  /// for the current device/install state.
  final bool flexibleAllowed;

  /// Short technical detail for the last failure, if any. Not shown
  /// verbatim to the user (the UI only ever shows the French copy from the
  /// spec); kept for logging/debugging (e.g. the Debug page).
  final String? errorMessage;

  const UpdateState({
    required this.status,
    this.updatePriority,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.errorMessage,
  });

  factory UpdateState.initial() => const UpdateState(status: UpdateStatus.idle);

  UpdateState copyWith({
    UpdateStatus? status,
    int? updatePriority,
    bool? immediateAllowed,
    bool? flexibleAllowed,
    String? errorMessage,
  }) {
    return UpdateState(
      status: status ?? this.status,
      updatePriority: updatePriority ?? this.updatePriority,
      immediateAllowed: immediateAllowed ?? this.immediateAllowed,
      flexibleAllowed: flexibleAllowed ?? this.flexibleAllowed,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
