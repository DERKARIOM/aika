import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:routerino/routerino.dart';

/// What the user wants to share through a new web share link.
enum ShareLinkSource {
  file(Icons.description_outlined, FilePickerOption.file),
  media(Icons.photo_library_outlined, FilePickerOption.media),
  folder(Icons.folder_outlined, FilePickerOption.folder),
  text(Icons.notes_rounded, null);

  const ShareLinkSource(this.icon, this.pickerOption);

  final IconData icon;

  /// The regular file picker used for this source, `null` for [text]
  /// (typed in a dialog, never routed to the chat like on the Send tab).
  final FilePickerOption? pickerOption;

  String get label {
    return switch (this) {
      ShareLinkSource.file => t.sendTab.picker.file,
      ShareLinkSource.media => t.sendTab.picker.media,
      ShareLinkSource.folder => t.sendTab.picker.folder,
      ShareLinkSource.text => t.sendTab.picker.text,
    };
  }

  /// The sources available on this platform, in the platform's usual order.
  static List<ShareLinkSource> forPlatform() {
    final pickerOptions = FilePickerOption.getOptionsForPlatform();
    return [
      for (final option in pickerOptions)
        for (final source in ShareLinkSource.values)
          if (source.pickerOption == option) source,
      ShareLinkSource.text,
    ];
  }
}

/// Bottom sheet opened by "Créer un lien de partage" on the Receive tab.
/// Pops with the chosen [ShareLinkSource], or nothing when dismissed.
class ShareLinkSourceSheet extends StatelessWidget {
  const ShareLinkSourceSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFr = LocaleSettings.currentLocale == AppLocale.fr;
    final sources = ShareLinkSource.forPlatform();

    return CustomBottomSheet(
      title: isFr ? 'Créer un lien de partage' : 'Create a share link',
      description: isFr ? 'Choisissez ce que vous voulez partager.' : 'Choose what you want to share.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              for (final source in sources) _SourceTile(source: source),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.wifi_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFr
                      ? 'Le destinataire ouvre le lien dans son navigateur, sur le même Wi-Fi, sans installer Aika.'
                      : 'The recipient opens the link in a browser, on the same Wi-Fi, without installing Aika.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final ShareLinkSource source;

  const _SourceTile({required this.source});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pop(source),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(source.icon, color: colorScheme.primary),
              Text(
                source.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
