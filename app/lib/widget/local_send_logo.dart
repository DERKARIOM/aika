import 'package:flutter/material.dart';
import 'package:localsend_app/gen/assets.gen.dart';

/// Displays the official AIKA logo mark.
///
/// The logo is shown in its real two-tone colors (no theme tinting) so that
/// it stays visually consistent everywhere in the app.
class LocalSendLogo extends StatelessWidget {
  final bool withText;

  const LocalSendLogo({required this.withText});

  @override
  Widget build(BuildContext context) {
    final logo = Assets.img.logo512.image(
      width: 200,
      height: 200,
    );

    if (withText) {
      return Column(
        children: [
          logo,
          const Text(
            'Aika',
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      return logo;
    }
  }
}
