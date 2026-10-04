import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/chat/chat_style.dart';

/// Drop files from the desktop onto [child] to send them in the chat.
///
/// Only active on desktop, while [enabled] and while its page is the one in
/// front: a drop target keeps receiving drag events when another page is
/// pushed over it (desktop_drop documents it), so a hidden conversation
/// must not swallow files dropped on another page.
class ChatDropZone extends StatefulWidget {
  final bool enabled;

  /// Called with the paths of the dropped files (folders are skipped).
  final ValueChanged<List<String>> onFilesDropped;
  final Widget child;

  const ChatDropZone({
    required this.enabled,
    required this.onFilesDropped,
    required this.child,
    super.key,
  });

  static bool get _isDesktop => const {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(defaultTargetPlatform);

  @override
  State<ChatDropZone> createState() => _ChatDropZoneState();
}

class _ChatDropZoneState extends State<ChatDropZone> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (_hovering != value) {
      setState(() => _hovering = value);
    }
  }

  void _onDragDone(DropDoneDetails details) {
    _setHovering(false);
    final paths = [
      for (final file in details.files)
        if (!FileSystemEntity.isDirectorySync(file.path)) file.path,
    ];
    if (paths.isNotEmpty) {
      widget.onFilesDropped(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatDropZone._isDesktop) {
      return widget.child;
    }
    final active = widget.enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    return DropTarget(
      enable: active,
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: _onDragDone,
      child: Stack(
        children: [
          widget.child,
          if (_hovering && active) const Positioned.fill(child: IgnorePointer(child: _DropOverlay())),
        ],
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(colors.accent.withValues(alpha: 0.10), colors.background.withValues(alpha: 0.92)),
        border: Border.all(color: colors.accent, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.file_upload_rounded, size: 56, color: colors.accent),
          const SizedBox(height: 12),
          Text(t.sendTab.placeItems, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.text)),
        ],
      ),
    );
  }
}
