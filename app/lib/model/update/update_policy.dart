/// What to do with an update that Google Play reports as available.
enum UpdateDecision {
  /// Nothing newer than the installed build.
  none,

  /// A newer build exists; proposing it is enough (flexible update).
  optional,

  /// The installed build is no longer supported (immediate update).
  mandatory,
}

/// Decides between an optional and a mandatory update from version codes
/// only, never from the displayed name ("1.1.4"): the versionCode / build
/// number is what Google Play itself compares, and it always increases.
///
/// Pure Dart (no Play Core) so it stays in FOSS builds and is unit tested.
class UpdatePolicy {
  /// Google Play update priority (0-5) at or above which an update is
  /// mandatory. The priority is attached to a release through the Google
  /// Play Developer API when it is rolled out.
  final int mandatoryPriority;

  const UpdatePolicy({required this.mandatoryPriority});

  /// [installedVersionCode] is this build's versionCode, [availableVersionCode]
  /// the one Google Play offers, [minimumVersionCode] the oldest build still
  /// supported (null when there is none). Unknown version codes are treated
  /// conservatively: they never make an update mandatory on their own.
  UpdateDecision decide({
    required int? installedVersionCode,
    required int? availableVersionCode,
    required int updatePriority,
    int? minimumVersionCode,
  }) {
    if (installedVersionCode != null && availableVersionCode != null && availableVersionCode <= installedVersionCode) {
      return UpdateDecision.none;
    }
    final belowMinimum = installedVersionCode != null && minimumVersionCode != null && installedVersionCode < minimumVersionCode;
    if (belowMinimum || updatePriority >= mandatoryPriority) {
      return UpdateDecision.mandatory;
    }
    return UpdateDecision.optional;
  }
}

/// The versionCode in a platform build number ("18"), or null if it is not
/// an integer.
int? parseVersionCode(String buildNumber) => int.tryParse(buildNumber.trim());

/// Where the oldest still-supported versionCode comes from.
///
/// It has to come from outside the app: an installed build cannot know that
/// a later release made it obsolete. A remote source (Firebase Remote Config,
/// a signed JSON file...) can be plugged in here later without touching the
/// update flow.
abstract class MinimumVersionSource {
  /// Null when there is no minimum, or when it cannot be read right now
  /// (offline...): the decision then relies on the Play priority alone.
  Future<int?> minimumVersionCode();
}

/// No minimum: mandatory updates are driven by the Google Play priority only.
class NoMinimumVersionSource implements MinimumVersionSource {
  const NoMinimumVersionSource();

  @override
  Future<int?> minimumVersionCode() async => null;
}
