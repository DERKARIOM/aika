import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/update_config.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/update_state.dart';
import 'package:localsend_app/provider/update_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

/// Blocks Aika while a mandatory update is applicable but not installed
/// (the user left Google Play's immediate update screen).
///
/// It cannot be popped by the user; update_provider.dart removes it once the
/// update is installed, no longer required, or Google Play cannot perform it
/// right now (offline, Play error), so it never leaves the user stuck.
/// "Mettre à jour" reopens Google Play's official screen.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = context.watch(updateProvider).status;
    final busy = status == UpdateStatus.checking || status == UpdateStatus.immediateInProgress;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: colorScheme.primaryContainer, shape: BoxShape.circle),
                      child: Icon(Icons.system_update_rounded, size: 40, color: colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _t(fr: 'Nouvelle version disponible', en: 'New version available'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        fr: "Une nouvelle version d'Aika est disponible. Veuillez mettre à jour l'application pour continuer.",
                        en: 'A new version of Aika is available. Please update the app to continue.',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                context.ref.redux(updateProvider).dispatchAsync(CheckForUpdateAction(trigger: UpdateCheckTrigger.gate)),
                              ),
                        child: busy
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_t(fr: 'Mettre à jour', en: 'Update')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => unawaited(launchUrl(Uri.parse(UpdateConfig.playStoreUrl), mode: LaunchMode.externalApplication)),
                      child: Text(_t(fr: 'Ouvrir Google Play', en: 'Open Google Play')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
