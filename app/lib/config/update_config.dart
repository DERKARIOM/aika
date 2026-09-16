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

  /// Minimum time between two automatic checks, so Aika doesn't hit the
  /// Play In-App Update API on every single app start / foreground event.
  static const Duration minCheckInterval = Duration(hours: 6);

  /// Google Play Console lets a release be tagged with an "update priority"
  /// from 0 (default, least urgent) to 5 (most urgent). At or above this
  /// threshold -- and only when Play itself reports that an immediate
  /// update is allowed for the device -- Aika asks for a blocking
  /// ("immediate") update instead of the default background ("flexible")
  /// one. Kept high on purpose: most releases should stay non-blocking, per
  /// "ne rends pas toutes les mises à jour obligatoires par défaut".
  static const int immediateUpdatePriorityThreshold = 4;

  /// Official Google Play Store URL for Aika, derived from the app's real
  /// applicationId (com.naniger.aika). Used as a manual fallback -- e.g.
  /// from the About page -- when Aika was not installed from Google Play,
  /// or when In-App Updates are unavailable for another reason (missing
  /// Play Services, unsupported device, ...).
  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.naniger.aika';
}
