import 'package:flutter/material.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/pages/web_send_page.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Whether the advanced network info is shown
final _showAdvancedProvider = StateProvider<bool>((ref) => false, debugLabel: '_showAdvancedProvider');

/// Whether the history button is shown
/// This extra boolean is needed to delay the animation
final _showHistoryButtonProvider = StateProvider<bool>((ref) => true, debugLabel: '_showHistoryButtonProvider');

class ReceiveTabVm {
  final String aliasSettings;
  final ServerState? serverState;
  final List<String> localIps;
  final bool showAdvanced;
  final bool showHistoryButton;
  final Future<void> Function() toggleAdvanced;

  /// Opens the web share page with a link (and QR code) that shares no
  /// files: browsers without Aika use it to send files to this device.
  final Future<void> Function(BuildContext context) onCreateShareLink;

  const ReceiveTabVm({
    required this.aliasSettings,
    required this.serverState,
    required this.localIps,
    required this.showAdvanced,
    required this.showHistoryButton,
    required this.toggleAdvanced,
    required this.onCreateShareLink,
  });
}

final receiveTabVmProvider = ViewProvider((ref) {
  final alias = ref.watch(settingsProvider.select((s) => s.alias));
  final networkInfo = ref.watch(localIpProvider).localIps;
  final serverState = ref.watch(serverProvider);
  final showAdvanced = ref.watch(_showAdvancedProvider);
  final showHistoryButton = ref.watch(_showHistoryButtonProvider);

  return ReceiveTabVm(
    aliasSettings: alias,
    serverState: serverState,
    localIps: networkInfo,
    showAdvanced: showAdvanced,
    showHistoryButton: showHistoryButton,
    toggleAdvanced: () async {
      if (showAdvanced) {
        ref.notifier(_showAdvancedProvider).setState((_) => false);
        await sleepAsync(200);
        ref.notifier(_showHistoryButtonProvider).setState((_) => true);
      } else {
        ref.notifier(_showAdvancedProvider).setState((_) => true);
        ref.notifier(_showHistoryButtonProvider).setState((_) => false);
      }
    },
    onCreateShareLink: (context) async {
      await context.push(() => const WebSendPage([]));
    },
  );
});
