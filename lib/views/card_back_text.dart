import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import 'faction_style.dart';

/// The back of a card that has one in the data but not as a picture.
///
/// 16 cards are in that position -- mostly promo and starter-deck
/// investigators, whose backs are deckbuilding rules. The other 6 have no back
/// text either and keep the placeholder.
class CardBackText extends StatelessWidget {
  const CardBackText({required this.card, required this.text, super.key});

  final model.Card card;
  final String text;

  /// Strips the markup those backs carry.
  ///
  /// A closed set: seven HTML tags and nine symbol tokens across the 16 cards.
  /// The tags go entirely, since bold and italic are not worth a rich-text
  /// renderer here; the symbols become the words they stand for.
  static String plain(String raw) {
    var text = raw.replaceAll('<hr>', '\n\n');
    _symbols.forEach((token, word) => text = text.replaceAll(token, word));
    return text
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static const _symbols = {
    '[guardian]': 'Guardian',
    '[seeker]': 'Seeker',
    '[rogue]': 'Rogue',
    '[mystic]': 'Mystic',
    '[survivor]': 'Survivor',
    '[skull]': 'Skull',
    '[cultist]': 'Cultist',
    '[tablet]': 'Tablet',
    '[elder_thing]': 'Elder Thing',
  };

  @override
  Widget build(BuildContext context) {
    final flavor = card.backFlavor;
    final border = BorderRadius.circular(12);

    // Grows to fit the text rather than holding a card's proportions: a fixed
    // card-shaped box clipped the longest back, which runs to 935 characters.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FactionStyle.color(
          card.factionCode,
          context,
        ).withValues(alpha: 0.12),
        borderRadius: border,
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            plain(text),
            style: TextStyle(
              fontSize: 16,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          if (flavor != null && flavor.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              height: 1 / MediaQuery.devicePixelRatioOf(context),
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            const SizedBox(height: 12),
            Text(
              plain(flavor),
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
