import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/update/peer_update.dart';
import 'package:localsend_app/provider/peer_update_provider.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:refena_flutter/refena_flutter.dart';

String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}

/// Shows [PeerUpdateBanner] above [child] when a transfer revealed a newer
/// Aika on the other device, and nothing otherwise.
///
/// The banner is part of the layout (not an overlay or a dialog): it pushes
/// the content down instead of covering it. The tree around [child] never
/// changes shape, so the state of the pages below is kept when the banner
/// appears or disappears.
class PeerUpdateBannerHost extends StatelessWidget {
  final Widget child;

  const PeerUpdateBannerHost({required this.child});

  @override
  Widget build(BuildContext context) {
    final hint = context.watch(peerUpdateProvider);
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          // No AnimatedSwitcher: a swiped-away Dismissible must leave the
          // tree at once. AnimatedSize alone slides the banner in and out.
          child: hint == null
              ? const SizedBox(width: double.infinity)
              : SafeArea(
                  key: ValueKey(hint.key),
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: PeerUpdateBanner(hint: hint),
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(
          // The banner already took the status bar inset.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: hint != null,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// « Nouvelle mise à jour disponible »: tapping it opens the store page for
/// this platform (Google Play on Android, naniger.com elsewhere, see
/// `UpdateConfig.updatePageUrlFor`). Can be closed or swiped away.
class PeerUpdateBanner extends StatelessWidget {
  final PeerUpdateHint hint;

  const PeerUpdateBanner({required this.hint});

  Future<void> _openUpdatePage(BuildContext context) async {
    final opened = await context.ref.notifier(peerUpdateProvider).openUpdatePage();
    if (!opened && context.mounted) {
      context.showSnackBar(
        _t(
          fr: "Impossible d'ouvrir la page de mise à jour. Rendez-vous sur naniger.com.",
          en: 'Could not open the update page. Please visit naniger.com.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = context.ref.notifier(peerUpdateProvider);
    final title = _t(fr: 'Nouvelle mise à jour disponible', en: 'New update available');
    final subtitle = _t(fr: "Une version plus récente d'Aika est disponible.", en: 'A newer version of Aika is available.');
    final action = _t(fr: 'Mettre à jour', en: 'Update');

    return Semantics(
      container: true,
      liveRegion: true,
      child: Dismissible(
        key: ValueKey('peer-update-${hint.key}'),
        onDismissed: (_) => notifier.dismiss(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: colorScheme.primaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.18)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openUpdatePage(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // On narrow phones the whole card is the action.
                    final showAction = constraints.maxWidth >= 440;
                    return Row(
                      children: [
                        _BannerIcon(colorScheme: colorScheme),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.78),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showAction) ...[
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _openUpdatePage(context),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: const StadiumBorder(),
                            ),
                            child: Text(action),
                          ),
                        ] else
                          Icon(Icons.chevron_right_rounded, color: colorScheme.onPrimaryContainer),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                          visualDensity: VisualDensity.compact,
                          color: colorScheme.onPrimaryContainer,
                          onPressed: notifier.dismiss,
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerIcon extends StatelessWidget {
  final ColorScheme colorScheme;

  const _BannerIcon({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.tertiary],
        ),
      ),
      child: Icon(Icons.system_update_alt_rounded, color: colorScheme.onPrimary, size: 22),
    );
  }
}
