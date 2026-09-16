// This file is Play-only: it wraps the `in_app_update` package, which
// itself wraps Google Play Core and cannot ship in FOSS (F-Droid) builds.
// It is entirely removed by support/scripts/remove_proprietary_dependencies.sh
// for those builds -- see that script and app/pubspec.yaml's
// `# [FOSS_REMOVE]` marker on the `in_app_update` dependency line.
//
// See app/docs/in-app-updates-2026-09.md for the full design write-up.

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:localsend_app/config/update_config.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/update_state.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/dialogs/update_dialog.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('UpdateProvider');

String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

final updateProvider = ReduxProvider<UpdateService, UpdateState>((ref) {
  return UpdateService();
});

class UpdateService extends ReduxNotifier<UpdateState> {
  @override
  UpdateState init() => UpdateState.initial();
}

/// Called from init.dart (app start) and main.dart (app resumed). Not an
/// action itself -- it only decides *whether* a check is worth doing right
/// now (platform support, feature flag, throttle interval) using the
/// [Ref] that's already available at both call sites, then fires
/// [CheckForUpdateAction] without blocking its caller.
void maybeCheckForUpdate(Ref ref) {
  if (!checkPlatformSupportInAppUpdate() || !UpdateConfig.autoCheckEnabled) {
    return;
  }

  final persistence = ref.read(persistenceProvider);
  final lastCheckMillis = persistence.getLastUpdateCheckMillis();
  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  if (lastCheckMillis != null && nowMillis - lastCheckMillis < UpdateConfig.minCheckInterval.inMilliseconds) {
    return;
  }

  // ignore: unawaited_futures
  persistence.setLastUpdateCheckMillis(nowMillis);
  // ignore: unawaited_futures
  ref.redux(updateProvider).dispatchAsync(CheckForUpdateAction());
}

/// Runs a single, discreet update check against Google Play. Never blocks
/// the caller and never surfaces a technical error to the user -- on any
/// failure Aika simply continues to work with the current version, per the
/// "l'application doit fonctionner normalement" requirement.
class CheckForUpdateAction extends AsyncReduxAction<UpdateService, UpdateState> {
  @override
  Future<UpdateState> reduce() async {
    if (!checkPlatformSupportInAppUpdate()) {
      return state.copyWith(status: UpdateStatus.unsupported);
    }

    dispatch(_SetStatusAction(UpdateStatus.checking));

    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return state.copyWith(status: UpdateStatus.notAvailable);
      }

      final newState = state.copyWith(
        status: UpdateStatus.available,
        updatePriority: info.updatePriority,
        immediateAllowed: info.immediateUpdateAllowed,
        flexibleAllowed: info.flexibleUpdateAllowed,
      );

      final wantsImmediate = info.updatePriority >= UpdateConfig.immediateUpdatePriorityThreshold;
      final useImmediate = wantsImmediate && info.immediateUpdateAllowed;
      final useFlexible = !useImmediate && info.flexibleUpdateAllowed;

      if (!useImmediate && !useFlexible) {
        // Play reports an update but neither flow is currently allowed for
        // this device/session (e.g. mid-throttle on Play's own side).
        // Nothing to show right now; the next periodic check will retry.
        return newState;
      }

      final context = Routerino.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        // ignore: use_build_context_synchronously
        await showDialog<void>(
          context: context,
          barrierDismissible: !useImmediate,
          builder: (_) => UpdateDialog(critical: useImmediate),
        );
      }

      return newState;
    } catch (e, st) {
      _logger.warning('Could not check for update', e, st);
      return state.copyWith(status: UpdateStatus.failed, errorMessage: e.toString());
    }
  }
}

/// Starts a background (flexible) update download. Triggered from
/// [UpdateDialog]'s "Mettre à jour" button for non-critical updates.
class StartFlexibleUpdateAction extends AsyncReduxAction<UpdateService, UpdateState> {
  @override
  Future<UpdateState> reduce() async {
    dispatch(_SetStatusAction(UpdateStatus.downloading));

    try {
      final result = await InAppUpdate.startFlexibleUpdate();

      if (result == AppUpdateResult.success) {
        final context = Routerino.navigatorKey.currentContext;
        if (context != null && context.mounted) {
          context.showSnackBarWithAction(
            text: _t(fr: 'Mise à jour prête à être installée.', en: 'Update ready to install.'),
            actionLabel: _t(fr: 'Redémarrer maintenant', en: 'Restart now'),
            onAction: () {
              context.ref.redux(updateProvider).dispatchAsync(CompleteFlexibleUpdateAction());
            },
          );
        }
        return state.copyWith(status: UpdateStatus.readyToInstall);
      }

      // AppUpdateResult.userDeniedUpdate or .inAppUpdateFailed: not an
      // error worth surfacing, the user can retry later (next automatic
      // check, or "Vérifier les mises à jour" in the About page).
      return state.copyWith(status: UpdateStatus.available);
    } catch (e, st) {
      _logger.warning('Flexible update download failed', e, st);
      return state.copyWith(status: UpdateStatus.failed, errorMessage: e.toString());
    }
  }
}

/// Finishes an already-downloaded flexible update (restarts the app to
/// apply it). Triggered from the "Redémarrer maintenant" snackbar action.
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

/// Starts a blocking (immediate) update, using Google Play's own full-screen
/// UI. Only used for updates at/above [UpdateConfig.immediateUpdatePriorityThreshold].
/// If the user cancels or it fails, Aika keeps running on the current
/// version rather than forcing a retry loop.
class PerformImmediateUpdateAction extends AsyncReduxAction<UpdateService, UpdateState> {
  @override
  Future<UpdateState> reduce() async {
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      if (result == AppUpdateResult.success) {
        // Play restarts the app as part of a successful immediate update;
        // this line is typically not reached.
        return state.copyWith(status: UpdateStatus.idle);
      }
      return state.copyWith(status: UpdateStatus.available);
    } catch (e, st) {
      _logger.warning('Immediate update failed', e, st);
      return state.copyWith(status: UpdateStatus.failed, errorMessage: e.toString());
    }
  }
}

/// Small synchronous helper action used to reflect an in-progress step
/// (e.g. "downloading") before awaiting the actual Play Core call, since a
/// single [AsyncReduxAction] only emits its final state once.
class _SetStatusAction extends ReduxAction<UpdateService, UpdateState> {
  final UpdateStatus status;

  _SetStatusAction(this.status);

  @override
  UpdateState reduce() => state.copyWith(status: status);
}
