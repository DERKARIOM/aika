import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/chat/chat_database_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/util/chat/chat_device_resolver.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Says, under the conversation's app bar, why messages do not go out right
/// now: encryption off on the peer, messages waiting for it, or a link
/// being opened. Hidden while the peer is online (nothing to explain).
class ChatConnectionBanner extends StatefulWidget {
  final String peerFingerprint;

  const ChatConnectionBanner({required this.peerFingerprint, super.key});

  @override
  State<ChatConnectionBanner> createState() => _ChatConnectionBannerState();
}

class _ChatConnectionBannerState extends State<ChatConnectionBanner> {
  /// Created once: a new stream per build would re-run the query.
  Stream<int>? _pendingCount;

  @override
  Widget build(BuildContext context) {
    final fingerprint = widget.peerFingerprint.toUpperCase();
    final online = watchPeerOnline(context, fingerprint);
    final https = context.watch(
      nearbyDevicesProvider.select((s) => s.devices.values.firstWhereOrNull((d) => d.fingerprint.toUpperCase() == fingerprint)?.https),
    );
    final pendingCount = _pendingCount ??= context.ref.read(chatDatabaseProvider).watchPendingCount(widget.peerFingerprint);

    return StreamBuilder<int>(
      stream: pendingCount,
      builder: (context, snapshot) {
        final pending = snapshot.data ?? 0;
        final (IconData, String)? content = switch ((online, https)) {
          (true, _) => null,
          (_, false) => (Icons.lock_open_rounded, t.chat.encryptionOff),
          _ when pending > 0 => (Icons.schedule_rounded, t.chat.pendingMessages(count: pending)),
          (_, true) => (Icons.sync_rounded, t.chat.connecting),
          _ => null,
        };
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: content == null ? const SizedBox(width: double.infinity) : _Banner(icon: content.$1, text: content.$2),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Banner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
