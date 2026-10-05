/// Centralized configuration for Android's Google Play In-App Updates
/// feature (see app/docs/in-app-updates-2026-09.md for the full write-up).
///
/// This file itself does not depend on Play Core / the `in_app_update`
/// package, so it stays in FOSS (F-Droid) builds. Only its *usage* in
/// update_provider.dart, init.dart and main.dart is guarded by
/// `// [FOSS_REMOVE_START]` / `// [FOSS_REMOVE_END]` markers, matching the
/// existing pattern used for in-app purchases.
class UpdateConfig {
  UpdateConfig._();

  /// Master switch. When false, Aika never checks for updates on its own
  /// (app start / resume); the manual "Vérifier les mises à jour" entry in
  /// the About page still works, since it is an explicit user action.
  static const bool autoCheckEnabled = true;

  /// Minimum time between two automatic checks when Aika comes back to the
  /// foreground. Not applied at app start (one cheap call to the Play Store
  /// app per launch) nor while a mandatory update is pending.
  static const Duration minCheckInterval = Duration(hours: 6);

  /// Google Play "update priority" (0-5) at or above which an update is
  /// mandatory: Aika then opens Google Play's immediate (full screen) update
  /// and blocks normal use until it is installed. Below it, the update is
  /// proposed in the background (flexible), as most releases should be.
  ///
  /// The priority is NOT set in the Play Console UI: it is attached to a
  /// release through the Google Play Developer API (`inAppUpdatePriority`
  /// of the track release, or fastlane `in_app_update_priority`) when the
  /// release is created, and cannot be changed afterwards.
  static const int immediateUpdatePriorityThreshold = 4;

  /// Official Google Play Store URL for Aika, derived from the app's real
  /// applicationId (com.naniger.aika). Used as a manual fallback -- e.g.
  /// from the About page -- when Aika was not installed from Google Play,
  /// or when In-App Updates are unavailable for another reason (missing
  /// Play Services, unsupported device, ...).
  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.naniger.aika';
}
