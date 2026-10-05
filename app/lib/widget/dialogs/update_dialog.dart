import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/update_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

/// Material 3 dialog proposing an optional Google Play update, downloaded in
/// the background (flexible flow) if accepted. Mandatory updates do not use
/// it: they open Google Play's own immediate screen directly, then
/// UpdateRequiredPage if the user leaves it.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.system_update_rounded, color: colorScheme.primary, size: 32),
      title: Text(_t(fr: "Une nouvelle version d'Aika est disponible", en: 'A new version of Aika is available')),
      content: Text(
        _t(
          fr: 'Profitez des dernières améliorations, corrections et fonctionnalités.',
          en: 'Enjoy the latest improvements, fixes and features.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t(fr: 'Plus tard', en: 'Later')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(context.ref.redux(updateProvider).dispatchAsync(StartFlexibleUpdateAction()));
          },
          child: Text(_t(fr: 'Mettre à jour', en: 'Update')),
        ),
      ],
    );
  }
}
