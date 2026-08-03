import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import 'faction_style.dart';

/// Where the transcoded card art lives in the asset bundle.
const cardImageDirectory = 'assets/CardImages';

/// The shape of a card, as a width-over-height ratio.
///
/// Investigator, act and agenda art is landscape; everything else is portrait.
double cardAspectRatio(model.Card card) => card.isLandscape ? 1.4 : 1 / 1.4;

/// One card's art, with a placeholder for the 27 cards that have none.
///
/// [maxPixels] is the longest edge to decode to, which is the whole of this
/// app's memory strategy. The bundle holds 7,742 images averaging 750x1050;
/// decoding one at full size costs about 3 MB, so a list that decoded them as
/// drawn would exhaust memory within a screen or two. **Every view showing card
/// art must pass a sensible value** -- there is no full-size path any more,
/// since the zoom view that needed one was removed.
class CardImageView extends StatelessWidget {
  const CardImageView({
    required this.card,
    required this.filename,
    required this.maxPixels,
    this.cornerRadius = 8,
    super.key,
  });

  final model.Card card;
  final String? filename;
  final int maxPixels;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final name = filename;
    final radius = BorderRadius.circular(cornerRadius);

    if (name == null) {
      return CardPlaceholder(card: card, cornerRadius: cornerRadius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image(
        // Both dimensions with `fit`, so the longest edge lands on maxPixels
        // and the aspect ratio is kept -- the same rule as the Swift app's
        // thumbnail decode. The cache key includes the size, so a card shown
        // in a row and on the detail screen is two entries, not one fought
        // over.
        image: ResizeImage(
          AssetImage('$cardImageDirectory/$name'),
          width: maxPixels,
          height: maxPixels,
          policy: ResizeImagePolicy.fit,
        ),
        fit: BoxFit.contain,
        // A card whose file is named but missing shows the placeholder rather
        // than a broken-image glyph.
        errorBuilder: (context, _, _) =>
            CardPlaceholder(card: card, cornerRadius: cornerRadius),
        frameBuilder: (context, child, frame, wasSynchronous) {
          if (wasSynchronous || frame != null) return child;
          // Grey of the right shape while decoding, so a scrolling list does
          // not jump as each row arrives.
          return AspectRatio(
            aspectRatio: cardAspectRatio(card),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemBackground
                    .resolveFrom(context),
                borderRadius: radius,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// What a card with no bundled art shows: its class colour and its name.
class CardPlaceholder extends StatelessWidget {
  const CardPlaceholder({
    required this.card,
    this.cornerRadius = 8,
    super.key,
  });

  final model.Card card;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: cardAspectRatio(card),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: FactionStyle.color(card.factionCode, context).withValues(
          alpha: 0.18,
        ),
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.photo,
                size: 20,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
              const SizedBox(height: 6),
              Text(
                card.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
