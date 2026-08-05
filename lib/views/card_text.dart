import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import 'card_row.dart';
import 'faction_style.dart';

/// A side of a card that the data describes but has no picture for.
///
/// The art is cropped from the Tabletop Simulator mod's save file and the SCED
/// campaign boxes, which between them miss only 124 fronts and 50 backs --
/// mostly sides the mod prints as the reverse of another card. Those stand in
/// as words.
///
/// The detail screen only. A row has no space for any of this and shows
/// `CardPlaceholder`, which at that size is a bare tinted rectangle.
///
/// [text] is nullable so a card with no rules text on the shown side is not a
/// name in the navigation bar above an empty screen: the card's identifying
/// details are shown instead. Every artless card currently has text, but the
/// fallback stays -- the pipeline pins that count, not the app.
class CardText extends StatelessWidget {
  const CardText({
    required this.card,
    required this.text,
    this.flavor,
    super.key,
  });

  final model.Card card;

  /// The side's rules text, or null where the data carries none.
  final String? text;

  /// The flavour printed on the same side as [text]. Passed in rather than read
  /// from [card], which carries one per side and cannot tell which this is.
  final String? flavor;

  /// Strips the markup this text carries.
  ///
  /// A closed set: six HTML tags and the symbols below. The tags go entirely,
  /// since bold and italic are not worth a rich-text renderer here; the symbols
  /// become the words they stand for.
  ///
  /// An unlisted token is stripped to its bare name rather than left in
  /// brackets, so a symbol a later box introduces reads as a word instead of as
  /// `[tdc_rune_x]`. The six Drowned City runes are already only that.
  static String plain(String raw) {
    var text = raw.replaceAll('<hr>', '\n\n');
    _symbols.forEach((token, word) => text = text.replaceAll(token, word));
    return text
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAllMapped(
          RegExp(r'\[([a-z_]+)\]'),
          (match) => match.group(1)!.replaceAll('_', ' '),
        )
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
    '[auto_fail]': 'Auto-fail',
    '[elder_sign]': 'Elder Sign',
    '[willpower]': 'Willpower',
    '[intellect]': 'Intellect',
    '[combat]': 'Combat',
    '[agility]': 'Agility',
    '[wild]': 'Wild',
    '[action]': 'Action',
    '[reaction]': 'Reaction',
    '[fast]': 'Fast',
    '[bless]': 'Bless',
    '[curse]': 'Curse',
    '[codex]': 'Codex',
    '[weapon]': 'Weapon',
    '[per_investigator]': 'per investigator',
  };

  @override
  Widget build(BuildContext context) {
    // Locals, because a field cannot be promoted to non-null.
    final text = this.text;
    final flavor = this.flavor;
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
          if (text != null)
            Text(
              plain(text),
              style: TextStyle(
                fontSize: 16,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            )
          else ...[
            // The name too, which the navigation bar ellipsises at 46
            // characters and is the only other thing naming the card.
            Text(
              card.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cardSubtitle(card),
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            if (card.traits != null) ...[
              const SizedBox(height: 8),
              Text(
                card.traits!,
                style: TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ],
          ],
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
