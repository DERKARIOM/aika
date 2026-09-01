import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/chat/chat_conversation_page.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_app/widget/list_tile/device_placeholder_list_tile.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Lets the user pick a nearby device to start a brand-new conversation
/// with. Reuses the exact same [DeviceListTile] used by the Send tab so the
/// device list looks and behaves identically.
class NewConversationPage extends StatelessWidget {
  const NewConversationPage();

  @override
  Widget build(BuildContext context) {
    final devices = context.watch(nearbyDevicesProvider.select((s) => s.devices.values.toList()));

    return Scaffold(
      appBar: basicAikaAppbar(t.chat.newConversation),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
        children: [
          if (devices.isEmpty) const DevicePlaceholderListTile(),
          ...devices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DeviceListTile(
                device: device,
                glass: true,
                onTap: () async {
                  await context.push(() => ChatConversationPage(peerFingerprint: device.fingerprint));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
