import 'package:flutter/material.dart';

extension SnackbarExt on BuildContext {
  void showSnackBar(String text) {
    final scaffold = ScaffoldMessenger.of(this);
    scaffold.removeCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  /// Same as [showSnackBar] but with a trailing action button (e.g. "Redemarrer
  /// maintenant" once a flexible in-app update finished downloading). Stays
  /// visible longer than the default snackbar duration since it requires a
  /// deliberate tap rather than being purely informational.
  void showSnackBarWithAction({
    required String text,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final scaffold = ScaffoldMessenger.of(this);
    scaffold.removeCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        content: Text(text),
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
        duration: const Duration(seconds: 10),
      ),
    );
  }
}
