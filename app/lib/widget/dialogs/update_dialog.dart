import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/update_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

/// Material 3 dialog shown when a Google Play In-App Update is available.
/// Text and buttons follow the exact French copy from the feature spec.
/// [critical] switches to the blocking ("immediate") wording and flow --
/// used only for releases at/above [UpdateConfig.immediateUpdatePriorityThreshold]
/// -- and removes the "Plus tard" dismiss option, since the update is meant
/// to be required in that case. Colors come entirely from [Theme.of(context)],
/// so this automatically follows Aika's Dark/Light theme.
class UpdateDialog extends StatelessWidget {
  final bool critical;

  const UpdateDialog({super.key, required this.critical});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !critical,
      child: AlertDialog(
        icon: Icon(Icons.system_update_rounded, color: colorScheme.primary, size: 32),
        title: Text(_t(fr: "Une nouvelle version d'Aika est disponible", en: 'A new version of Aika is available')),
        content: Text(
          critical
              ? _t(
                  fr: 'Cette mise à jour est nécessaire pour continuer à utiliser Aika.',
                  en: 'This update is required to keep using Aika.',
                )
              : _t(
                  fr: 'Profitez des dernières améliorations, corrections et fonctionnalités.',
                  en: 'Enjoy the latest improvements, fixes and features.',
                ),
        ),
        actions: [
          if (!critical)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t(fr: 'Plus tard', en: 'Later')),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (critical) {
                unawaited(context.ref.redux(updateProvider).dispatchAsync(PerformImmediateUpdateAction()));
              } else {
                unawaited(context.ref.redux(updateProvider).dispatchAsync(StartFlexibleUpdateAction()));
              }
            },
            child: Text(_t(fr: 'Mettre à jour', en: 'Update')),
          ),
        ],
      ),
    );
  }
}
