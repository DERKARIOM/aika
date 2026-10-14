import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';

String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

/// Blocking loader shown while picked files are being prepared (copied to
/// the cache on Android, read and measured elsewhere), so the user knows
/// the selection was taken into account.
///
/// A compact card over the dimmed page: round-capped spinner in the accent
/// color, a short title and, when known, how many files are being prepared.
class LoadingDialog extends StatelessWidget {
  /// Number of files being prepared, `null` when not known yet (e.g. while
  /// the Android picker still copies them).
  final int? fileCount;

  const LoadingDialog({this.fileCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = fileCount;
    final title = switch (count) {
      null => _t(fr: 'Préparation des fichiers…', en: 'Preparing files…'),
      1 => _t(fr: 'Préparation du fichier…', en: 'Preparing the file…'),
      _ => _t(fr: 'Préparation de $count fichiers…', en: 'Preparing $count files…'),
    };

    return PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Material(
              color: colorScheme.surfaceContainerHigh,
              elevation: 6,
              shadowColor: Colors.black45,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                child: Semantics(
                  liveRegion: true,
                  label: title,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          strokeCap: StrokeCap.round,
                          color: colorScheme.primary,
                          backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(
                          fr: 'Quelques secondes pour les fichiers volumineux.',
                          en: 'A few seconds for large files.',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
