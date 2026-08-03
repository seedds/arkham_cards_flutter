import 'package:flutter/cupertino.dart';

/// The five classes, plus neutral and mythos, in the colours the game prints.
abstract final class FactionStyle {
  static Color color(String faction, BuildContext context) => switch (faction) {
    'guardian' => const Color.fromRGBO(51, 89, 158, 1),
    'seeker' => const Color.fromRGBO(201, 140, 41, 1),
    'rogue' => const Color.fromRGBO(38, 112, 71, 1),
    'mystic' => const Color.fromRGBO(97, 71, 140, 1),
    'survivor' => const Color.fromRGBO(179, 56, 51, 1),
    'neutral' => const Color.fromRGBO(107, 107, 115, 1),
    // The only colour that has to adapt: mythos is near-black, which is
    // invisible against a dark background.
    'mythos' => CupertinoDynamicColor.withBrightness(
      color: const Color.fromRGBO(33, 33, 38, 1),
      darkColor: const Color.fromRGBO(184, 184, 194, 1),
    ).resolveFrom(context),
    _ => CupertinoColors.systemGrey.resolveFrom(context),
  };

  static String name(String faction) => switch (faction) {
    'guardian' => 'Guardian',
    'seeker' => 'Seeker',
    'rogue' => 'Rogue',
    'mystic' => 'Mystic',
    'survivor' => 'Survivor',
    'neutral' => 'Neutral',
    'mythos' => 'Mythos',
    _ => _capitalized(faction),
  };
}

String _capitalized(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
