import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
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
        return Scaffold(
          appBar: basicAikaAppbar(t.donationPage.title),
          body: Stack(
            children: [
              ResponsiveListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 50),
                  Center(
                    child: Text(
                      t.donationPage.info,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 50),
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
                  if (vm.platformSupportPayment) _StoreDonation(vm) else const _LinkDonation(),
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

class _LinkDonation extends StatelessWidget {
  const _LinkDonation();

  static const _phoneNumber = '94961793';

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Text(
          'Envoyez votre don via',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
        ),
        const SizedBox(height: 15),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          children: const [
            _MobileMoneyBadge(label: 'Nita'),
            _MobileMoneyBadge(label: 'Amana'),
          ],
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: () async {
            await Clipboard.setData(const ClipboardData(text: _phoneNumber));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Numéro copié')),
              );
            }
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phone, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                _phoneNumber,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.copy, size: 18, color: primaryColor),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileMoneyBadge extends StatelessWidget {
  final String label;

  const _MobileMoneyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: primaryColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}