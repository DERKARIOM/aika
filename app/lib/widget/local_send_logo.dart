import 'package:flutter/material.dart';
import 'package:localsend_app/gen/assets.gen.dart';

/// Displays the AIKA logo mark.
///
/// By default this shows the official logo in its real two-tone colors (no
/// theme tinting), so it stays visually consistent everywhere in the app.
///
/// Set [legacy] to true to show the previous logo instead (tinted to the
/// current theme color, as it was before the rebrand) — used on the Receive
/// page only, at the user's request.
class LocalSendLogo extends StatelessWidget {
  final bool withText;
  final bool legacy;

  const LocalSendLogo({required this.withText, this.legacy = false});

  @override
  Widget build(BuildContext context) {
    final Widget logo;
    if (legacy) {
      logo = ColorFiltered(
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.primary,
          BlendMode.srcATop,
        ),
        child: Assets.img.logo512Legacy.image(
          width: 200,
          height: 200,
        ),
      );
    } else {
      logo = Assets.img.logo512.image(
        width: 200,
        height: 200,
      );
    }

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
