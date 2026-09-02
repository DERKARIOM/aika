import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/donation_methods.dart';
import 'package:localsend_app/model/state/purchase_state.dart';
import 'package:localsend_app/pages/donation/donation_page_vm.dart';
// [FOSS_REMOVE_START]
import 'package:localsend_app/provider/purchase_provider.dart';
// [FOSS_REMOVE_END]
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';

class DonationPage extends StatelessWidget {
  const DonationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      provider: (ref) => donationPageVmProvider,
      // [FOSS_REMOVE_START]
      init: (context) => context.redux(purchaseProvider).dispatchAsync(FetchPricesAndPurchasesAction()), // ignore: discarded_futures
      // [FOSS_REMOVE_END]
      builder: (context, vm) {
        // The in-app-purchase flow (_StoreDonation) is only meaningful once the
        // store actually returned real priced products. As long as no store
        // listing is configured (vm.prices is empty), users see the mobile
        // money section (_SupportSection) instead, so the page always shows a
        // working way to contribute instead of a store UI with nothing to buy.
        final showStoreDonation = vm.platformSupportPayment && vm.prices.isNotEmpty;

        return Scaffold(
          appBar: basicAikaAppbar(t.donationPage.title),
          body: Stack(
            children: [
              ResponsiveListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 32),
                  const _FreeHeader(),
                  const SizedBox(height: 32),
                  if (vm.purchased.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Center(
                        child: Text(
                          t.donationPage.thanks,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ),
                  if (showStoreDonation) _StoreDonation(vm) else const _SupportSection(),
                  const SizedBox(height: 32),
                ],
              ),
              if (vm.pending)
                Container(
                  color: Colors.black.withValues(alpha: 0.1),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// "Aika is 100% free" hero block shown at the top of the donation page,
/// regardless of which contribution method is available below.
class _FreeHeader extends StatelessWidget {
  const _FreeHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          t.donationPage.freeTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          t.donationPage.freeMessage,
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Text(
          t.donationPage.supportMessage,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StoreDonation extends StatelessWidget {
  final DonationPageVm vm;

  const _StoreDonation(this.vm);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...PurchaseItem.values.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton.icon(
              onPressed: vm.purchased.contains(item) ? null : () => vm.purchase(item),
              icon: const Icon(Icons.favorite),
              label: Text(t.donationPage.donate(amount: vm.prices[item] ?? '...')),
            ),
          );
        }),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: vm.restore,
          icon: const Icon(Icons.restore),
          label: Text(t.donationPage.restore),
        ),
      ],
    );
  }
}

/// The "Support Aika" section: one modern Material 3 card per mobile money
/// method (see `lib/model/donation_methods.dart` for the centralized list),
/// each showing its logo, its name, and a button to copy the shared
/// donation number (the raw number itself is never displayed on screen).
/// This is the primary donation flow on Aika's main target platforms
/// today, since no real store products are configured yet.
class _SupportSection extends StatelessWidget {
  const _SupportSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          t.donationPage.methodsIntro,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
        ),
        const SizedBox(height: 16),
        ...kDonationMethods.map(
          (method) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DonationMethodCard(method: method),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t.donationPage.footerThanks,
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _DonationMethodCard extends StatefulWidget {
  final DonationMethod method;

  const _DonationMethodCard({required this.method});

  @override
  State<_DonationMethodCard> createState() => _DonationMethodCardState();
}

class _DonationMethodCardState extends State<_DonationMethodCard> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: kDonationPhoneNumber));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The raw number is intentionally never rendered here: only the logo and
    // the service name are shown, and the number is copied to the clipboard
    // without being displayed on screen (see kDonationPhoneNumber usage in
    // _copy() above).
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: widget.method.logo.image(width: 56, height: 56, fit: BoxFit.contain),
            ),
            const SizedBox(height: 10),
            Text(
              widget.method.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _CopyButton(copied: _copied, onTap: _copy),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy button with a light inline animation (no Snackbar): the icon and
/// label swap to a checkmark and "Copied!" for a couple of seconds after a
/// tap, then revert on their own.
class _CopyButton extends StatelessWidget {
  final bool copied;
  final VoidCallback onTap;

  const _CopyButton({required this.copied, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: copied ? null : onTap,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
        child: Icon(
          copied ? Icons.check : Icons.copy,
          key: ValueKey(copied),
          size: 18,
        ),
      ),
      label: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          copied ? t.donationPage.numberCopied : t.donationPage.copyNumber,
          key: ValueKey(copied),
        ),
      ),
    );
  }
}
