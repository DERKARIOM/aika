import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:logging/logging.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('ShareAikaPage');

enum _ShareAikaStatus { idle, preparing, shared, error }

/// "Partager Aika": lets a user who already has Aika send its own APK to a nearby
/// device that doesn't have it yet, via Android's native Sharesheet (Bluetooth, Nearby
/// Share, or any other compatible app) — see [shareOwnApkAndroid] for why this is
/// deliberately delegated to Android rather than implemented as a custom Bluetooth
/// engine inside Aika.
class ShareAikaPage extends StatefulWidget {
  const ShareAikaPage();

  @override
  State<ShareAikaPage> createState() => _ShareAikaPageState();
}

class _ShareAikaPageState extends State<ShareAikaPage> {
  _ShareAikaStatus _status = _ShareAikaStatus.idle;
  OwnApkShareResult? _lastResult;

  Future<void> _onTapShare() async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.share_rounded, color: colorScheme.primary, size: 36),
        title: Text(t.shareAikaPage.confirmTitle),
        content: Text(t.shareAikaPage.confirmBody),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(false),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () => dialogContext.pop(true),
            child: Text(t.shareAikaPage.confirmCta),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _status = _ShareAikaStatus.preparing;
    });

    try {
      final result = await shareOwnApkAndroid();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ShareAikaStatus.shared;
        _lastResult = result;
      });
    } catch (e) {
      _logger.warning('Failed to share own APK', e);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ShareAikaStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: basicAikaAppbar(t.shareAikaPage.title),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 30),
          const LocalSendLogo(withText: false),
          const SizedBox(height: 24),
          Text(
            t.shareAikaPage.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            t.shareAikaPage.bluetoothUnavailableNotice,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),
          if (_status == _ShareAikaStatus.preparing) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Text(t.shareAikaPage.preparing, textAlign: TextAlign.center),
          ] else
            Center(
              child: FilledButton.icon(
                onPressed: _onTapShare,
                icon: const Icon(Icons.share_rounded),
                label: Text(t.shareAikaPage.shareButton),
              ),
            ),
          if (_status == _ShareAikaStatus.shared) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastResult == null
                          ? t.shareAikaPage.shared
                          : '${t.shareAikaPage.shared}\n${_lastResult!.fileName} · v${_lastResult!.versionName}',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_status == _ShareAikaStatus.error) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.shareAikaPage.error)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
