import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/chat_tab.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/chat/chat_conversations_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum HomeTab {
  receive(Icons.wifi),
  send(Icons.send),
  chat(Icons.chat_bubble_outline_rounded),
  settings(Icons.settings)
  ;

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.receive:
        return t.receiveTab.title;
      case HomeTab.send:
        return t.sendTab.title;
      case HomeTab.chat:
        return t.chat.title;
      case HomeTab.settings:
        return t.settingsTab.title;
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  bool _dragAndDropIndicator = false;

  @override
  void initState() {
    super.initState();

    ensureRef((ref) async {
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
    });
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        if (event.files.length == 1 && Directory(event.files.first.path).existsSync()) {
          // user dropped a directory
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(event.files.first.path));
        } else {
          // user dropped one or more files
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: event.files,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        vm.changeTab(HomeTab.send);
      },
      child: ResponsiveBuilder(
        builder: (sizingInformation) {
          return Scaffold(
            body: Row(
              children: [
                if (!sizingInformation.isMobile)
                  Stack(
                    children: [
                    NavigationRail(
                    selectedIndex: vm.currentTab.index,
                      onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                      extended: sizingInformation.isDesktop,
                      backgroundColor: Theme.of(context).cardColorWithElevation,
                      // Pastille de sélection pleine (opaque) + textes/icônes garantis lisibles :
                      // l'icône sélectionnée est DANS la pastille (fond #42B998) -> onPrimary ;
                      // le libellé sélectionné est SOUS la pastille, sur le fond de la barre -> onSurface.
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      selectedIconTheme: IconThemeData(color: Theme.of(context).colorScheme.onPrimary),
                      unselectedIconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      selectedLabelTextStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
                      unselectedLabelTextStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      leading: sizingInformation.isDesktop
                          ? Column(
                                children: [
                                  checkPlatform([TargetPlatform.macOS])
                                      ? // considered adding some extra space so it looks more natural
                                        SizedBox(height: 40)
                                      : SizedBox(height: 20),
                                  const Text(
                                    'Aika',
                                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 20),
                                ],
                              )
                            : checkPlatform([TargetPlatform.macOS])
                            ? SizedBox(
                                height: 20,
                              )
                            : null,
                        destinations: HomeTab.values.map((tab) {
                          return NavigationRailDestination(
                            icon: _HomeTabIcon(tab: tab),
                            label: Text(tab.label),
                          );
                        }).toList(),
                      ),
                      // makes the top draggable
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: MoveWindow(),
                      ),
                    ],
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      PageView(
                        controller: vm.controller,
                        physics: const NeverScrollableScrollPhysics(),
                        children: const [
                          SafeArea(child: ReceiveTab()),
                          SafeArea(child: SendTab()),
                          SafeArea(child: ChatTab()),
                          SettingsTab(),
                        ],
                      ),
                      if (_dragAndDropIndicator)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.file_download, size: 128),
                              const SizedBox(height: 30),
                              Text(t.sendTab.placeItems, style: Theme.of(context).textTheme.titleLarge),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: sizingInformation.isMobile
                ? NavigationBarTheme(
              // NavigationBar n'expose pas de paramètre `iconTheme` direct : la couleur de
              // l'icône par état (sélectionné/non-sélectionné) ne peut être surchargée que
              // via NavigationBarThemeData (contrairement à NavigationRail, qui l'accepte
              // directement en paramètre du widget).
              data: NavigationBarThemeData(
                iconTheme: WidgetStateProperty.resolveWith((states) {
                  final colorScheme = Theme.of(context).colorScheme;
                  return IconThemeData(
                    color: states.contains(WidgetState.selected) ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: vm.currentTab.index,
                onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                backgroundColor: Theme.of(context).colorScheme.surface,
                // Même logique que la NavigationRail desktop : pastille pleine + contraste garanti
                // pour les états sélectionné/non-sélectionné (icône ET libellé).
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final colorScheme = Theme.of(context).colorScheme;
                  return TextStyle(
                    color: states.contains(WidgetState.selected) ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                    fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.normal,
                  );
                }),
                destinations: HomeTab.values.map((tab) {
                  return NavigationDestination(icon: _HomeTabIcon(tab: tab), label: tab.label);
                }).toList(),
              ),
            )
                : null,
          );
        },
      ),
    );
  }
}

/// A tab icon showing an unread-message badge for [HomeTab.chat].
/// A separate widget so only this small icon rebuilds when the unread
/// count changes, not the whole navigation bar/rail.
class _HomeTabIcon extends StatelessWidget {
  final HomeTab tab;

  const _HomeTabIcon({required this.tab});

  @override
  Widget build(BuildContext context) {
    if (tab != HomeTab.chat) {
      return Icon(tab.icon);
    }

    final unread = context.watch(chatConversationsProvider.select((c) => c.totalUnreadCount));
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: Icon(tab.icon),
    );
  }
}
