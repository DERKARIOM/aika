import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Whether a send screen (this page or the "Envoyer à…" sheet) is shown.
/// The device discovery uses it to decide whether a slower scan is worth
/// starting (it used to check the old Send tab).
class SendScreenVisibility {
  SendScreenVisibility._();

  static int _count = 0;

  static bool get visible => _count > 0;

  static void enter() => _count++;

  static void leave() => _count = _count > 0 ? _count - 1 : 0;
}

/// The former "Envoyer" tab, now a page: same selection, same pickers,
/// same device list and transfer. Opened from the Home send sheets, the
/// share intent, drag and drop, and the paste shortcut.
class SendFilesPage extends StatefulWidget {
  const SendFilesPage();

  /// Whether the page is currently in the navigation stack.
  static bool get isOpen => _openCount > 0;
  static int _openCount = 0;

  @override
  State<SendFilesPage> createState() => _SendFilesPageState();
}

class _SendFilesPageState extends State<SendFilesPage> {
  @override
  void initState() {
    super.initState();
    SendFilesPage._openCount++;
    SendScreenVisibility.enter();
  }

  @override
  void dispose() {
    SendFilesPage._openCount--;
    SendScreenVisibility.leave();
    super.dispose();
  }

  /// Files dropped on the page join the selection, as on the old tab.
  Future<void> _onDrop(DropDoneDetails event) async {
    final selection = context.ref.redux(selectedSendingFilesProvider);
    if (event.files.length == 1 && Directory(event.files.first.path).existsSync()) {
      await selection.dispatchAsync(AddDirectoryAction(event.files.first.path));
    } else {
      await selection.dispatchAsync(AddFilesAction(files: event.files, converter: CrossFileConverters.convertXFile));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: ModalRoute.of(context)?.isCurrent ?? true,
      onDragDone: _onDrop,
      child: Scaffold(
        appBar: basicAikaAppbar(t.sendTab.title),
        body: const SafeArea(child: SendTab()),
      ),
    );
  }
}

/// Shows the send page (once: does nothing when it is already open).
/// Safe to call from providers and app start-up: the push waits for the
/// next frame so the home page is in place first.
void openSendScreen() {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (SendFilesPage.isOpen) {
      return;
    }
    // ignore: discarded_futures
    Routerino.context.push(() => const SendFilesPage());
  });
  SchedulerBinding.instance.ensureVisualUpdate();
}
