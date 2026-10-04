import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/provider/chat/chat_conversations_provider.dart';
import 'package:localsend_app/provider/chat/chat_link_provider.dart';
import 'package:localsend_app/provider/chat/peer_link_manager.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/debug_entry.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// For every chat contact: is a chat link (WebSocket) up, and if not, why
/// the last attempt failed. This is how to tell why messages are waiting.
class ChatDebugPage extends StatefulWidget {
  const ChatDebugPage({super.key});

  @override
  State<ChatDebugPage> createState() => _ChatDebugPageState();
}

class _ChatDebugPageState extends State<ChatDebugPage> {
  /// Link state lives in [PeerLinkManager], which is not observable:
  /// refreshed periodically while this page is open.
  late final Timer _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 2), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final links = context.ref.read(peerLinkManagerProvider);
    final conversations = context.watch(chatConversationsProvider);
    final devices = context.watch(nearbyDevicesProvider.select((s) => s.devices.values.toList()));
    final fingerprints = {
      ...conversations.map((c) => c.peerFingerprint.toUpperCase()),
      ...links.readyPeers,
    };

    return Scaffold(
      appBar: basicAikaAppbar('Chat Debugging'),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        maxWidth: 700,
        children: [
          if (fingerprints.isEmpty) const Text('No chat contact yet.'),
          for (final fingerprint in fingerprints)
            _PeerLinkCard(
              fingerprint: fingerprint,
              alias: conversations.firstWhereOrNull((c) => c.peerFingerprint.toUpperCase() == fingerprint)?.peerAlias,
              device: devices.firstWhereOrNull((d) => d.fingerprint.toUpperCase() == fingerprint),
              links: links,
              onConnected: () => setState(() {}),
            ),
        ],
      ),
    );
  }
}

class _PeerLinkCard extends StatelessWidget {
  final String fingerprint;
  final String? alias;

  /// The peer as discovery currently sees it, if it does.
  final Device? device;
  final PeerLinkManager links;
  final VoidCallback onConnected;

  const _PeerLinkCard({
    required this.fingerprint,
    required this.alias,
    required this.device,
    required this.links,
    required this.onConnected,
  });

  @override
  Widget build(BuildContext context) {
    final ready = links.isReady(fingerprint);
    final diagnostics = links.diagnosticsOf(fingerprint);
    final ip = device?.ip;
    final port = device?.port;
    final https = device?.https ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DebugEntry(name: alias ?? device?.alias ?? 'Unknown device', value: fingerprint),
            DebugEntry(name: 'Chat link', value: ready ? 'ready (protocol v${links.versionOf(fingerprint)})' : 'none'),
            DebugEntry(name: 'Discovery', value: _describeDevice(device)),
            DebugEntry(name: 'Last attempt', value: _describeAttempt(diagnostics)),
            DebugEntry(name: 'Last disconnection', value: _describeDisconnect(diagnostics)),
            if (!ready && https && ip != null && port != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await links.ensureLink(PeerAddress(fingerprint: fingerprint, ip: ip, port: port));
                  onConnected();
                },
                child: const Text('Connect now'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _describeDevice(Device? device) {
    if (device == null) {
      return 'not seen on the network';
    }
    final protocol = device.https ? 'HTTPS' : 'HTTP: encryption off, no chat link possible';
    return '${device.ip}:${device.port} · $protocol';
  }

  static String _describeAttempt(PeerLinkDiagnostics? diagnostics) {
    final status = diagnostics?.lastAttempt;
    final at = diagnostics?.lastAttemptAt;
    if (status == null || at == null) {
      return 'never';
    }
    final error = diagnostics!.lastError;
    return '${status.name} at ${_time(at)}${error != null ? ' · $error' : ''}';
  }

  static String _describeDisconnect(PeerLinkDiagnostics? diagnostics) {
    final reason = diagnostics?.lastDisconnectReason;
    final at = diagnostics?.lastDisconnectAt;
    if (reason == null || at == null) {
      return 'never';
    }
    return '$reason at ${_time(at)}';
  }

  static String _time(DateTime at) => at.toLocal().toIso8601String().substring(11, 19);
}
