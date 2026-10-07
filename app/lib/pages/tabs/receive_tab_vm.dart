import 'package:flutter/material.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/pages/web_send_page.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class ReceiveTabVm {
  final String aliasSettings;

  /// `null` while the server is not running (not ready to receive).
  final ServerState? serverState;

  /// Local IP addresses, the most likely primary one first.
  final List<String> localIps;

  /// Opens the web share page with a link (and QR code) that shares no
  /// files: browsers without Aika use it to send files to this device.
  final Future<void> Function(BuildContext context) onCreateShareLink;

  const ReceiveTabVm({
    required this.aliasSettings,
    required this.serverState,
    required this.localIps,
    required this.onCreateShareLink,
  });

  bool get isReceiving => serverState != null;
}

final receiveTabVmProvider = ViewProvider((ref) {
  final alias = ref.watch(settingsProvider.select((s) => s.alias));
  final localIps = ref.watch(localIpProvider).localIps;
  final serverState = ref.watch(serverProvider);

  return ReceiveTabVm(
    aliasSettings: alias,
    serverState: serverState,
    localIps: localIps,
    onCreateShareLink: (context) async {
      await context.push(() => const WebSendPage([]));
    },
  );
});
