import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import '../models/card_database.dart';
import '../models/deck.dart';
import '../models/deck_contents.dart';
import 'card_detail_view.dart';
import 'card_row.dart';

/// One deck's cards, grouped by type.
class DeckDetailView extends StatelessWidget {
  DeckDetailView({required this.deck, required this.database, super.key})
    : contents = DeckContents(deck, database);

  final Deck deck;
  final CardDatabase database;
  final DeckContents contents;

  @override
  Widget build(BuildContext context) {
    final investigator = contents.investigator;
    final sideCards = contents.sideCards;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: CupertinoNavigationBar(middle: Text(deck.name)),
      child: SafeArea(
        child: ListView(
          children: [
            if (investigator != null)
              CupertinoListSection.insetGrouped(
                // "33 cards" rather than a bare 33: under this header a bare
                // number would read as a count of investigators. Nothing else
                // on screen gives the deck's total.
                header: Text('Investigator (${contents.cardCount} cards)'),
                children: [
                  _row(
                    context,
                    card: investigator,
                    quantity: null,
                    sequence: contents.pageSequence,
                  ),
                ],
              ),
            for (final section in contents.sections)
              CupertinoListSection.insetGrouped(
                header: Text('${section.title} (${section.cardCount})'),
                children: [
                  for (final entry in section.entries)
                    _row(
                      context,
                      card: entry.card,
                      quantity: entry.quantity,
                      sequence: contents.pageSequence,
                    ),
                ],
              ),
            for (final section in contents.sideSections)
              CupertinoListSection.insetGrouped(
                header: Text(
                  'Side Deck \u00b7 ${section.title} (${section.cardCount})',
                ),
                children: [
                  for (final entry in section.entries)
                    // Side-deck rows page among themselves: a tap here does
                    // not carry on into the main deck.
                    _row(
                      context,
                      card: entry.card,
                      quantity: entry.quantity,
                      sequence: sideCards,
                    ),
                ],
              ),
            if (contents.unresolvedCodes.isNotEmpty)
              _UnresolvedFooter(count: contents.unresolvedCodes.length),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required model.Card card,
    required int? quantity,
    required List<model.Card> sequence,
  }) => CupertinoListTile.notched(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    onTap: () => Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => CardDetailView(
          card: card,
          cards: sequence,
          database: database,
        ),
      ),
    ),
    title: Row(
      children: [
        // A fixed column even when empty. Omitting the widget for the
        // investigator pulled its art out of line with every row below it.
        SizedBox(
          width: 22,
          child: Text(
            quantity == null ? '' : '$quantity\u00d7',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: CardRow(card: card)),
      ],
    ),
  );
}

/// Names the cards this bundle does not carry, rather than showing fewer.
///
/// An imported deck can list a card from a box newer than this app's data, and
/// a deck quietly showing 28 of its 33 would read as correct.
class _UnresolvedFooter extends StatelessWidget {
  const _UnresolvedFooter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          CupertinoIcons.exclamationmark_triangle,
          size: 15,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            count == 1
                ? '1 card in this deck is not in this app\u2019s card data.'
                : '$count cards in this deck are not in this app\u2019s card '
                      'data.',
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      ],
    ),
  );
}
