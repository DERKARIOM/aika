// This file is Play-only: it wraps the `in_app_update` package, which
// itself wraps Google Play Core and cannot ship in FOSS (F-Droid) builds.
// It is entirely removed by support/scripts/remove_proprietary_dependencies.sh
// for those builds -- see that script and app/pubspec.yaml's
// `# [FOSS_REMOVE]` marker on the `in_app_update` dependency line.
//
// Flow (Android + Google Play only, see checkPlatformSupportInAppUpdate):
// - app start: always checks; app resume: at most every
//   UpdateConfig.minCheckInterval, or every time while a mandatory update is
//   pending.
// - optional update -> Aika's dialog, then Play's flexible (background) flow.
// - mandatory update (UpdatePolicy, from version codes and Play's priority)
//   -> Play's official immediate screen directly. If the user leaves it,
//   UpdateRequiredPage blocks Aika until the update is installed.
// - Play unreachable / update not applicable -> Aika keeps working; local
//   transfers never depend on this check.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:localsend_app/config/update_config.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/update_state.dart';
import 'package:localsend_app/model/update/update_policy.dart';
import 'package:localsend_app/pages/update_required_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/update_dialog.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('UpdateProvider');

String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

/// Play Core errors meaning In-App Updates cannot work on this install
/// (not installed from Google Play, no Play Store, API unavailable).
final _unsupportedError = RegExp('ERROR_(APP_NOT_OWNED|API_NOT_AVAILABLE|PLAY_STORE_NOT_FOUND)|\\((-10|-3|-9)\\)');

/// Why a check runs; decides throttling and whether Play's screen may open
/// on its own.
enum UpdateCheckTrigger {
  appStart,
  resume,

  /// "Vérifier les mises à jour" in the About page.
  manual,

  /// "Mettre à jour" on [UpdateRequiredPage].
  gate,
}

/// Source of the minimum supported versionCode. None for now: mandatory
/// updates come from the Google Play priority. Override this provider to
/// plug a remote configuration in later.
final minimumVersionSourceProvider = Provider<MinimumVersionSource>((ref) => const NoMinimumVersionSource());

final updateProvider = ReduxProvider<UpdateService, UpdateState>((ref) {
  return UpdateService(
    persistence: ref.read(persistenceProvider),
    minimumVersionSource: ref.read(minimumVersionSourceProvider),
  );
});

class UpdateService extends ReduxNotifier<UpdateState> {
  static const _policy = UpdatePolicy(mandatoryPriority: UpdateConfig.immediateUpdatePriorityThreshold);

  final PersistenceService _persistence;
  final MinimumVersionSource _minimumVersionSource;

  /// One check at a time (app start and resume can fire together).
  bool _checking = false;

  /// Play's immediate screen was opened by this process. The plugin then
  /// reopens it by itself when an interrupted update is resumed, so Aika
  /// must not open it a second time.
  bool _immediateLaunched = false;

  /// The optional-update dialog is shown once per launch, not on each resume.
  bool _optionalOffered = false;

  Route<void>? _gate;

  UpdateService({
    required PersistenceService persistence,
    required MinimumVersionSource minimumVersionSource,
  }) : _persistence = persistence,
       _minimumVersionSource = minimumVersionSource;

  @override
  UpdateState init() => UpdateState.initial();

  /// Shows [UpdateRequiredPage] over the app, once.
  void _showGate() {
    if (_gate?.isActive ?? false) {
      return;
    }
    final navigator = Routerino.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    final route = MaterialPageRoute<void>(builder: (_) => const UpdateRequiredPage(), fullscreenDialog: true);
    _gate = route;
    unawaited(navigator.push(route));
  }

  /// Removes [UpdateRequiredPage]: the update is installed, no longer
  /// applicable, or Google Play cannot perform it right now.
  void _releaseGate() {
    final route = _gate;
    _gate = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }
}

/// Called from init.dart (app start) and main.dart (app resumed). Decides
/// whether a check is worth doing now, then runs it without blocking the
/// caller.
void maybeCheckForUpdate(Ref ref, {required UpdateCheckTrigger trigger}) {
  if (!checkPlatformSupportInAppUpdate() || !UpdateConfig.autoCheckEnabled) {
    return;
  }

  final state = ref.read(updateProvider);
  final pending = state.mandatoryPending || state.status == UpdateStatus.readyToInstall;
  if (trigger == UpdateCheckTrigger.resume && !pending) {
    final lastCheckMillis = ref.read(persistenceProvider).getLastUpdateCheckMillis();
    final elapsed = DateTime.now().millisecondsSinceEpoch - (lastCheckMillis ?? 0);
    if (elapsed >= 0 && elapsed < UpdateConfig.minCheckInterval.inMilliseconds) {
      return;
    }
  }

  unawaited(ref.redux(updateProvider).dispatchAsync(CheckForUpdateAction(trigger: trigger)));
}

/// Asks Google Play whether an update is available and runs the matching
/// flow. Never throws: on any failure Aika keeps working on this version.
class CheckForUpdateAction extends AsyncReduxAction<UpdateService, UpdateState> {
  final UpdateCheckTrigger trigger;

  CheckForUpdateAction({this.trigger = UpdateCheckTrigger.manual});

  @override
  Future<UpdateState> reduce() async {
    if (!checkPlatformSupportInAppUpdate()) {
      return state.copyWith(status: UpdateStatus.unsupported);
    }
    if (notifier._checking) {
      return state;
    }
    notifier._checking = true;
    try {
      return await _check();
    } catch (e, st) {
      _logger.warning('Update check failed', e, st);
      notifier._releaseGate();
      return state.copyWith(status: UpdateStatus.failed, errorMessage: e.toString());
    } finally {
      notifier._checking = false;
    }
  }

  Future<UpdateState> _check() async {
    dispatch(_SetStateAction(state.copyWith(status: UpdateStatus.checking)));

    final AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate();
    } on PlatformException catch (e) {
      // Offline, Play Store missing, not installed from Google Play...
      // Without Play, a mandatory update cannot be applied: never block.
      final unsupported = _unsupportedError.hasMatch('${e.code} ${e.message}');
      _logger.info('Play In-App Update unavailable: ${e.code} ${e.message}');
      notifier._releaseGate();
      return state.copyWith(
        status: unsupported ? UpdateStatus.unsupported : UpdateStatus.failed,
        errorMessage: '${e.code}: ${e.message}',
      );
    }

    // Only a successful check counts for the resume throttle.
    await notifier._persistence.setLastUpdateCheckMillis(DateTime.now().millisecondsSinceEpoch);

    final checked = state.copyWith(
      installedVersionCode: parseVersionCode((await PackageInfo.fromPlatform()).buildNumber),
      availableVersionCode: info.availableVersionCode,
      updatePriority: info.updatePriority,
      immediateAllowed: info.immediateUpdateAllowed,
      flexibleAllowed: info.flexibleUpdateAllowed,
    );
    _logger.info('Play update info: $info');

    if (info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress) {
      // An immediate update was interrupted (app closed, process killed).
      // Google requires resuming it; within the same process the plugin
      // already does it on resume.
      if (notifier._immediateLaunched) {
        return checked.copyWith(status: UpdateStatus.immediateInProgress);
      }
      return _runImmediate(checked);
    }

    if (info.installStatus == InstallStatus.downloaded) {
      // A flexible update was downloaded before Aika was closed.
      _offerRestart();
      return checked.copyWith(status: UpdateStatus.readyToInstall);
    }

    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      notifier._releaseGate();
      return checked.copyWith(status: UpdateStatus.notAvailable);
    }

    int? minimumVersionCode;
    try {
      minimumVersionCode = await notifier._minimumVersionSource.minimumVersionCode();
    } catch (e) {
      _logger.info('Minimum version unavailable: $e');
    }

    final decision = UpdateService._policy.decide(
      installedVersionCode: checked.installedVersionCode,
      availableVersionCode: info.availableVersionCode,
      updatePriority: info.updatePriority,
      minimumVersionCode: minimumVersionCode,
    );

    switch (decision) {
      case UpdateDecision.none:
        notifier._releaseGate();
        return checked.copyWith(status: UpdateStatus.notAvailable);
      case UpdateDecision.mandatory when info.immediateUpdateAllowed:
        if (trigger == UpdateCheckTrigger.resume && (notifier._gate?.isActive ?? false)) {
          // Back in Aika with the blocking screen up: it already offers
          // "Mettre à jour", Play's screen is not reopened on every resume.
          return checked.copyWith(status: UpdateStatus.updateRequired);
        }
        return _runImmediate(checked);
      case UpdateDecision.mandatory:
        // Play does not allow an immediate update right now: blocking Aika
        // would leave the user stuck. Proposed as optional instead; the next
        // check tries again.
        _logger.info('Mandatory update, but immediate update not allowed by Play');
        notifier._releaseGate();
        return _offerOptional(checked, info);
      case UpdateDecision.optional:
        notifier._releaseGate();
        return _offerOptional(checked, info);
    }
  }

  /// Opens Google Play's immediate update screen.
  Future<UpdateState> _runImmediate(UpdateState base) async {
    dispatch(_SetStateAction(base.copyWith(status: UpdateStatus.immediateInProgress)));
    notifier._immediateLaunched = true;
    final AppUpdateResult result;
    try {
      result = await InAppUpdate.performImmediateUpdate();
    } catch (e, st) {
      _logger.warning('Immediate update could not start', e, st);
      notifier._releaseGate();
      return base.copyWith(status: UpdateStatus.failed, errorMessage: e.toString());
    }
    switch (result) {
      case AppUpdateResult.success:
        // Play restarts Aika once installed; usually not reached.
        notifier._releaseGate();
        return base.copyWith(status: UpdateStatus.idle);
      case AppUpdateResult.userDeniedUpdate:
        notifier._showGate();
        return base.copyWith(status: UpdateStatus.updateRequired);
      case AppUpdateResult.inAppUpdateFailed:
        // Play failed on its side: not blocking, retried at the next check.
        notifier._releaseGate();
        return base.copyWith(status: UpdateStatus.failed, errorMessage: 'IN_APP_UPDATE_FAILED');
    }
  }

  Future<UpdateState> _offerOptional(UpdateState base, AppUpdateInfo info) async {
    final next = base.copyWith(status: UpdateStatus.available);
    if (!info.flexibleUpdateAllowed) {
      return next;
    }
    if (notifier._optionalOffered && trigger != UpdateCheckTrigger.manual) {
      return next;
    }
    final context = Routerino.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return next;
    }
    notifier._optionalOffered = true;
    dispatch(_SetStateAction(next));
    await showDialog<void>(context: context, builder: (_) => const UpdateDialog());
    return state;
  }
}

/// Starts a background (flexible) update download. Triggered from
/// [UpdateDialog]'s "Mettre à jour" button.
class StartFlexibleUpdateAction extends AsyncReduxAction<UpdateService, UpdateState> {
  @override
  Future<UpdateState> reduce() async {
    dispatch(_SetStateAction(state.copyWith(status: UpdateStatus.downloading)));

    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        _offerRestart();
        return state.copyWith(status: UpdateStatus.readyToInstall);
      }
      // Declined or failed: proposed again at the next launch, or from
      // "Vérifier les mises à jour" in the About page.
      return state.copyWith(status: UpdateStatus.available);
    } catch (e, st) {
      _logger.warning('Flexible update download failed', e, st);
      return state.copyWith(status: UpdateStatus.failed, errorMessage: e.toString());
    }
  }
}

/// Installs an already-downloaded flexible update (Play restarts Aika).
class CompleteFlexibleUpdateAction extends AsyncReduxAction<UpdateService, UpdateState> {
  @override
  Future<UpdateState> reduce() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
      return state.copyWith(status: UpdateStatus.idle);
    } catch (e, st) {
      _logger.warning('Could not complete flexible update', e, st);
      return state.copyWith(status: UpdateStatus.failed, errorMessage: e.toString());
    }
  }
}

/// Proposes to restart Aika on a downloaded flexible update.
void _offerRestart() {
  final context = Routerino.navigatorKey.currentContext;
  if (context == null || !context.mounted) {
    return;
  }
  context.showSnackBarWithAction(
    text: _t(fr: 'Mise à jour prête à être installée.', en: 'Update ready to install.'),
    actionLabel: _t(fr: 'Redémarrer maintenant', en: 'Restart now'),
    onAction: () {
      unawaited(context.ref.redux(updateProvider).dispatchAsync(CompleteFlexibleUpdateAction()));
    },
  );
}

/// Publishes an intermediate state while an action is still running (a
/// single [AsyncReduxAction] only emits its final state).
class _SetStateAction extends ReduxAction<UpdateService, UpdateState> {
  final UpdateState next;

  _SetStateAction(this.next);

  @override
  UpdateState reduce() => next;
}
