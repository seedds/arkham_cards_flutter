import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import '../models/deck.dart';
import 'card_image_view.dart';
import 'faction_style.dart';

/// One deck as a row: its investigator's art, its name, and its size.
class DeckRow extends StatelessWidget {
  const DeckRow({required this.deck, required this.investigator, super.key});

  /// Landscape, because investigator art is. A square box would letterbox it
  /// into a sliver, and sizing by width alone would double the row height.
  static const thumbnailWidth = 44.0;
  static const thumbnailHeight = 32.0;

  /// 44pt at 3x is 132px; 168 matches CardRow.
  static const thumbnailPixels = 168;

  final Deck deck;
  final model.Card? investigator;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: thumbnailWidth,
        height: thumbnailHeight,
        child: investigator == null
            // Still a row: the deck is real and its other cards may all
            // resolve. Nothing to name here, so nothing is named.
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: CupertinoColors.secondarySystemBackground.resolveFrom(
                    context,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              )
            : Center(
                child: CardImageView(
                  card: investigator!,
                  filename: investigator!.frontImage,
                  maxPixels: thumbnailPixels,
                  cornerRadius: 3,
                ),
              ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              deck.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                height: 20 / 15,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            Text(
              _subtitle(deck, investigator),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 13 / 11,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

String _subtitle(Deck deck, model.Card? investigator) => [
  // Dropped when it would only repeat the deck's name, which it does for all
  // ten starters -- each is named after the investigator on the box.
  if (investigator != null && investigator.name != deck.name) investigator.name,
  if (investigator != null) investigator.factions.map(FactionStyle.name).join('/'),
  '${deck.cardCount} cards',
].join(' \u00b7 ');
