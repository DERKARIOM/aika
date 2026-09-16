import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/debug/debug_page.dart';
// [FOSS_REMOVE_START]
import 'package:localsend_app/config/update_config.dart';
import 'package:localsend_app/model/state/update_state.dart';
import 'package:localsend_app/provider/update_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:refena_flutter/refena_flutter.dart';
// [FOSS_REMOVE_END]
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:routerino/routerino.dart';
import 'package:url_launcher/url_launcher.dart';

final _translatorWithGithubRegex = RegExp(r'(.+) \(@([\w\-_]+)\)');

// [FOSS_REMOVE_START]
String _t({required String fr, required String en}) {
  return LocaleSettings.currentLocale == AppLocale.fr ? fr : en;
}
// [FOSS_REMOVE_END]

class AboutPage extends StatelessWidget {
  const AboutPage();

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: basicAikaAppbar(t.aboutPage.title),
      body: ResponsiveListView(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        children: [
          const SizedBox(height: 20),
          const LocalSendLogo(withText: true),
          Text(
            '© ${DateTime.now().year} Bachir Abdoul Kader',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(t.aboutPage.description.join('\n\n')),
          const SizedBox(height: 20),
          Text(t.aboutPage.author, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text.rich(
            _buildContributor(
              label: 'Bachir Abdoul Kader',
              primaryColor: primaryColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(t.aboutPage.academicContext),
          const SizedBox(height: 20),
          Text(t.aboutPage.openSourceTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(t.aboutPage.openSourceDescription),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton(
                onPressed: () async {
                  await launchUrl(Uri.parse('https://naniger.com'));
                },
                child: const Text('naniger.com'),
              ),
              TextButton(
                onPressed: () async {
                  await launchUrl(Uri.parse('https://www.apache.org/licenses/LICENSE-2.0'));
                },
                child: const Text('Apache License 2.0'),
              ),
              TextButton(
                onPressed: () async {
                  await context.push(() => const LicensePage());
                },
                child: const Text('License Notices'),
              ),
              TextButton(
                onPressed: () async {
                  await context.push(() => const DebugPage());
                },
                child: const Text('Debugging'),
              ),
              // [FOSS_REMOVE_START]
              if (checkPlatformSupportInAppUpdate())
                TextButton(
                  onPressed: () async {
                    final result = await context.ref.redux(updateProvider).dispatchAsync(CheckForUpdateAction());
                    if (!context.mounted) {
                      return;
                    }
                    switch (result.status) {
                      case UpdateStatus.notAvailable:
                        context.showSnackBar(
                          _t(
                            fr: "Vous utilisez déjà la dernière version d'Aika.",
                            en: 'You are already using the latest version of Aika.',
                          ),
                        );
                        break;
                      case UpdateStatus.unsupported:
                        context.showSnackBarWithAction(
                          text: _t(
                            fr: "La vérification des mises à jour n'est disponible que via Google Play.",
                            en: 'Update checking is only available through Google Play.',
                          ),
                          actionLabel: _t(fr: 'Ouvrir Google Play', en: 'Open Google Play'),
                          onAction: () async {
                            await launchUrl(Uri.parse(UpdateConfig.playStoreUrl), mode: LaunchMode.externalApplication);
                          },
                        );
                        break;
                      case UpdateStatus.failed:
                        context.showSnackBar(
                          _t(
                            fr: 'Impossible de vérifier les mises à jour pour le moment.',
                            en: 'Could not check for updates right now.',
                          ),
                        );
                        break;
                      case UpdateStatus.available:
                      case UpdateStatus.idle:
                      case UpdateStatus.checking:
                      case UpdateStatus.downloading:
                      case UpdateStatus.readyToInstall:
                        // "available" already showed its own dialog from
                        // CheckForUpdateAction; the others aren't reachable
                        // as the immediate result of a fresh manual check.
                        break;
                    }
                  },
                  child: Text(_t(fr: 'Vérifier les mises à jour', en: 'Check for updates')),
                ),
              // [FOSS_REMOVE_END]
            ],
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }
}

/// Displays the contributor name and links to their github profile.
InlineSpan _buildContributor({required String label, required Color primaryColor, bool newLine = false}) {
  final newLineStr = newLine ? '\n' : '';

  if (label.startsWith('@')) {
    // Only github name
    return TextSpan(
      text: '$newLineStr$label',
      style: TextStyle(color: primaryColor),
      recognizer: TapGestureRecognizer()
        ..onTap = () async {
          await launchUrl(Uri.parse('https://github.com/${label.substring(1)}'), mode: LaunchMode.externalApplication);
        },
    );
  }

  final match = _translatorWithGithubRegex.firstMatch(label);
  if (match != null) {
    // Full name and github name
    final fullName = match.group(1)!;
    final githubName = match.group(2)!;
    return TextSpan(
      children: [
        TextSpan(text: '$newLineStr$fullName'),
        const TextSpan(text: ' '),
        TextSpan(
          text: '@$githubName',
          style: TextStyle(color: primaryColor),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              await launchUrl(Uri.parse('https://github.com/$githubName'), mode: LaunchMode.externalApplication);
            },
        ),
      ],
    );
  }

  // Only full name
  return TextSpan(text: '$newLineStr$label');
}
