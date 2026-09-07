import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/qr_pairing_display_page.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/tabs/receive_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/animations/initial_fade_transition.dart';
import 'package:localsend_app/widget/column_list_view.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

enum _QuickSaveMode {
  off,
  favorites,
  on,
}

class ReceiveTab extends StatelessWidget {
  const ReceiveTab();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch(receiveTabVmProvider);

    return Stack(
      children: [
        checkPlatform([TargetPlatform.macOS])
            ? SizedBox(height: 50, child: MoveWindow())
            : SizedBox(height: 0, width: 0), // makes the top part that's not occupied by another widget draggable
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ResponsiveListView.defaultMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: ColumnListView(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InitialFadeTransition(
                          duration: const Duration(milliseconds: 300),
                          delay: const Duration(milliseconds: 200),
                          child: Consumer(
                            builder: (context, ref) {
                              final animations = ref.watch(animationProvider);
                              final activeTab = ref.watch(homePageControllerProvider.select((state) => state.currentTab));
                              return RotatingWidget(
                                duration: const Duration(seconds: 15),
                                spinning: vm.serverState != null && animations && activeTab == HomeTab.receive,
                                child: const LocalSendLogo(withText: false, legacy: true),
                              );
                            },
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(vm.serverState?.alias ?? vm.aliasSettings, style: const TextStyle(fontSize: 48)),
                        ),
                        const SizedBox(height: 12),
                        InitialFadeTransition(
                          duration: const Duration(milliseconds: 300),
                          delay: const Duration(milliseconds: 500),
                          child: vm.serverState == null
                              ? Text(
                                  t.general.offline,
                                  style: const TextStyle(fontSize: 18),
                                  textAlign: TextAlign.center,
                                )
                              : Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: vm.localIps.map((ip) => ip.visualId).toSet().map((id) => _IdChip(id: id)).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(
                      child: Column(
                        children: [
                          Text(t.general.quickSave),
                          const SizedBox(height: 18),
                          _QuickSaveSpinner(vm: vm),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),
        ),
        _InfoBox(vm),
        _CornerButtons(
          showAdvanced: vm.showAdvanced,
          showHistoryButton: vm.showHistoryButton,
          toggleAdvanced: vm.toggleAdvanced,
        ),
      ],
    );
  }
}

class _QuickSaveSpinner extends StatelessWidget {
  final ReceiveTabVm vm;

  const _QuickSaveSpinner({required this.vm});

  _QuickSaveMode get _selectedMode {
    if (vm.quickSaveFromFavoritesSettings) return _QuickSaveMode.favorites;
    if (vm.quickSaveSettings) return _QuickSaveMode.on;
    return _QuickSaveMode.off;
  }

  String _labelFor(_QuickSaveMode mode) {
    switch (mode) {
      case _QuickSaveMode.off:
        return t.receiveTab.quickSave.off;
      case _QuickSaveMode.favorites:
        return t.receiveTab.quickSave.favorites;
      case _QuickSaveMode.on:
        return t.receiveTab.quickSave.on;
    }
  }

  Future<void> _onSelect(BuildContext context, _QuickSaveMode mode) async {
    switch (mode) {
      case _QuickSaveMode.off:
        await vm.onSetQuickSave(context, false);
        if (context.mounted) {
          await vm.onSetQuickSaveFromFavorites(context, false);
        }
        break;
      case _QuickSaveMode.favorites:
        await vm.onSetQuickSave(context, false);
        if (context.mounted) {
          await vm.onSetQuickSaveFromFavorites(context, true);
        }
        break;
      case _QuickSaveMode.on:
        await vm.onSetQuickSaveFromFavorites(context, false);
        if (context.mounted) {
          await vm.onSetQuickSave(context, true);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedMode;
    final modes = _QuickSaveMode.values;
    final selectedIndex = modes.indexOf(selected);
    const segmentWidth = 80.0;
    final primaryColor = Theme.of(context).colorScheme.primary;

    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: segmentWidth * selectedIndex,
              width: segmentWidth,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: modes.map((mode) {
                final isSelected = mode == selected;
                return SizedBox(
                  width: segmentWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => _onSelect(context, mode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Text(
                        _labelFor(mode),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 0.3,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdChip extends StatelessWidget {
  final String id;

  const _IdChip({required this.id});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // était 16 / 8
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16), // était 20
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Text(
          id,
          style: TextStyle(
            fontSize: 16, // était 22
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0, // était 1.2
            color: colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _CornerButtons extends StatelessWidget {
  final bool showAdvanced;
  final bool showHistoryButton;
  final Future<void> Function() toggleAdvanced;

  const _CornerButtons({
    required this.showAdvanced,
    required this.showHistoryButton,
    required this.toggleAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Tooltip(
              message: t.qrPairing.display.buttonTooltip,
              child: CustomIconButton(
                onPressed: () async {
                  await context.push(() => const QrPairingDisplayPage());
                },
                child: const Icon(Icons.qr_code),
              ),
            ),
            if (!showAdvanced)
              AnimatedOpacity(
                opacity: showHistoryButton ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: CustomIconButton(
                  onPressed: () async {
                    await context.push(() => const ReceiveHistoryPage());
                  },
                  child: const Icon(Icons.history),
                ),
              ),
            CustomIconButton(
              key: const ValueKey('info-btn'),
              onPressed: toggleAdvanced,
              child: const Icon(Icons.info),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final ReceiveTabVm vm;

  const _InfoBox(this.vm);

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      crossFadeState: vm.showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
      firstChild: Container(),
      secondChild: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: IntrinsicColumnWidth(),
                  2: IntrinsicColumnWidth(),
                },
                children: [
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.alias),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 30),
                        child: SelectableText(vm.serverState?.alias ?? '-'),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.ip),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (vm.localIps.isEmpty) Text(t.general.unknown),
                          ...vm.localIps.map((ip) => SelectableText(ip)),
                        ],
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.port),
                      const SizedBox(width: 10),
                      SelectableText(vm.serverState?.port.toString() ?? '-'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
