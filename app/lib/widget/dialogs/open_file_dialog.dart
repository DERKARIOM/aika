import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/file_clipboard.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/open_folder.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:path/path.dart' as path;
import 'package:routerino/routerino.dart';

class OpenFileDialog extends StatefulWidget {
  final String filePath;
  final FileType fileType;
  final bool openGallery;

  /// Every file received in the session, for "Copier". Defaults to
  /// [filePath] alone.
  final List<String>? filePaths;

  const OpenFileDialog({
    super.key,
    required this.filePath,
    required this.fileType,
    required this.openGallery,
    this.filePaths,
  });

  static Future<void> open(
    BuildContext context, {
    required String filePath,
    required FileType fileType,
    required bool openGallery,
    List<String>? filePaths,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => OpenFileDialog(
        filePath: filePath,
        fileType: fileType,
        openGallery: openGallery,
        filePaths: filePaths,
      ),
    );
  }

  @override
  State<OpenFileDialog> createState() => _OpenFileDialogState();
}

class _OpenFileDialogState extends State<OpenFileDialog> {
  late Timer _timer;
  int _countdown = 5; // Starting countdown value

  /// Received files that can be put on the clipboard on this platform.
  late final List<String> _copyable = copyableReceivedFiles(
    widget.openGallery ? const [] : (widget.filePaths ?? [widget.filePath]),
  );
  bool _copied = false;

  Future<void> _copy() async {
    final copied = await copyReceivedFilesToClipboard(_copyable);
    if (!mounted) {
      return;
    }
    // Stays open once copied: no countdown hurrying the user.
    _timer.cancel();
    setState(() => _copied = copied);
    if (!copied) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(t.general.error)),
      );
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();
        if (context.mounted) {
          context.pop(); // Automatically close the dialog
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.dialogs.openFile.title),
      content: Text(t.dialogs.openFile.content),
      actions: [
        TextButton(
          onPressed: () async {
            if (widget.openGallery && defaultTargetPlatform == TargetPlatform.android) {
              await android_channel.openGallery();
            } else {
              await openFile(context, widget.fileType, widget.filePath);
            }
          },
          child: Text(t.general.open),
        ),
        if (!widget.openGallery)
          TextButton(
            onPressed: () async => await openFolder(
              folderPath: File(widget.filePath).parent.path,
              fileName: path.basename(widget.filePath),
            ),
            child: Text(t.receiveHistoryPage.entryActions.showInFolder),
          ),
        if (_copyable.isNotEmpty)
          TextButton.icon(
            onPressed: _copied ? null : _copy,
            icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
            label: Text(
              _copied
                  ? t.general.copiedToClipboard
                  : _copyable.length > 1
                  ? '${t.general.copy} (${_copyable.length})'
                  : t.general.copy,
            ),
          ),
        TextButton(
          onPressed: () {
            _timer.cancel();
            context.pop();
          },
          child: Text(_timer.isActive ? '${t.general.close} ($_countdown)' : t.general.close),
        ),
      ],
    );
  }
}
