import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:localsend_app/widget/dialogs/message_input_dialog.dart';
import 'package:refena_flutter/refena_flutter.dart';
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

/// Asks for a source with [ShareLinkSourceSheet], lets the user pick from it
/// and returns the picked files (empty when cancelled).
///
/// The regular pickers are reused (same permissions, Android cache handling
/// and folder support as the Send tab): they add to the send selection, and
/// only the files added by this pick are returned.
Future<List<CrossFile>> pickFilesForShareLink(BuildContext context, Ref ref) async {
  final source = await context.pushBottomSheet(() => const ShareLinkSourceSheet());
  if (source is! ShareLinkSource || !context.mounted) {
    return const [];
  }

  final before = ref.read(selectedSendingFilesProvider);
  final pickerOption = source.pickerOption;
  if (pickerOption == null) {
    final text = await showDialog<String>(context: context, builder: (_) => const MessageInputDialog());
    if (text == null || text.trim().isEmpty) {
      return const [];
    }
    ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: text));
  } else {
    await ref.global.dispatchAsync(PickFileAction(option: pickerOption, context: context));
  }

  return ref.read(selectedSendingFilesProvider).where((file) => !before.any((old) => identical(old, file))).toList();
}

/// Bottom sheet listing what can be added to a web share link.
/// Pops with the chosen [ShareLinkSource], or nothing when dismissed.
class ShareLinkSourceSheet extends StatelessWidget {
  const ShareLinkSourceSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFr = LocaleSettings.currentLocale == AppLocale.fr;
    final sources = ShareLinkSource.forPlatform();

    return CustomBottomSheet(
      title: isFr ? 'Ajouter des fichiers au lien' : 'Add files to the link',
      description: isFr ? 'Ils pourront être téléchargés depuis le lien.' : 'They can be downloaded from the link.',
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
                      ? 'Les appareils déjà connectés au lien voient les nouveaux fichiers sans recharger la page.'
                      : 'Devices already on the link see the new files without reloading the page.',
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
