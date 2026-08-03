import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import '../models/type_names.dart';
import 'card_image_view.dart';
import 'faction_style.dart';

/// One card as a row: a thumbnail, its name, and where it comes from.
///
/// Shared by the browse list, the version picker on the detail screen and the
/// deck screen, so it carries no list-specific styling -- callers supply the
/// insets.
class CardRow extends StatelessWidget {
  const CardRow({required this.card, super.key});

  /// A fixed square, so a portrait card and a landscape one make rows of the
  /// same height. Sizing by width alone made investigator rows a third taller.
  static const thumbnailSize = 28.0;

  /// 28pt at 3x is 84px; 168 leaves headroom for the version picker, which
  /// draws the same row slightly larger on some screens.
  static const thumbnailPixels = 168;

  final model.Card card;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: thumbnailSize,
        height: thumbnailSize,
        child: Center(
          // The front only. For a two-sided pair the sides are different
          // cards, so falling back to the back would caption one card's art
          // with another card's name.
          child: CardImageView(
            card: card,
            filename: card.frontImage,
            maxPixels: thumbnailPixels,
            cornerRadius: 3,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                // The line height is the system's for this size, which a bare
                // fontSize does not carry: without it the two lines crowd
                // together and the row stands 12pt shorter. Measured.
                height: 20 / 15,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            Text(
              _subtitle(card),
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

/// Type, class, level and box, which is what tells two rows apart.
///
/// The number is `printedNumber` rather than `position`, because a box prints
/// two cards at one position: the two `Hunter's Hunger` read `#53a` and `#53b`,
/// and without that 356 rows were byte-identical.
String _subtitle(model.Card card) => [
  typeName(card.typeCode),
  card.factions.map(FactionStyle.name).join('/'),
  if (card.level > 0) 'Level ${card.level}',
  '${card.packName} #${card.printedNumber}',
].join(' \u00b7 ');
