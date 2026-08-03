import 'package:arkham_cards/models/deck.dart';
import 'package:arkham_cards/models/deck_contents.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

/// Run against the real bundled `decks.json` and `cards.json`, for the same
/// reason the card tests are: the decks are derived from upstream pack files by
/// a rule -- level 0 and not the investigator -- that upstream never stated, so
/// a change in how those files are written should fail here rather than show up
/// as a deck that is quietly missing cards.
void main() {
  Deck starter(String investigatorCode) =>
      starters.firstWhere((deck) => deck.investigatorCode == investigatorCode);

  group('the bundled decks', () {
    test('ten starter decks', () {
      // A new one appearing means a pack was added to STARTER_PACKS in the
      // build script, which is a decision to make deliberately.
      expect(starters.length, 10);
      expect(starters.map((deck) => deck.id).toSet().length, 10);
    });

    test('starter deck sizes', () {
      // 33 cards each, except the two investigators with extra signatures.
      const expected = {
        '60101': (33, 'Nathaniel Cho'),
        '60151': (33, 'Tommy Muldoon'),
        '60201': (33, 'Harvey Walters'),
        '60251': (33, 'Carolyn Fern'),
        '60301': (33, 'Winifred Habbamock'),
        '60351': (35, 'André Patel, four signatures'),
        '60401': (33, 'Jacqueline Fine'),
        '60451': (33, 'Marie Lambeau'),
        '60501': (35, 'Stella Clark'),
        '60551': (33, 'Miguel de la Cruz'),
      };
      final sizes = {
        for (final deck in starters) deck.investigatorCode: deck.cardCount,
      };
      expect(sizes.length, 10, reason: 'investigator codes are distinct');
      for (final entry in expected.entries) {
        final (size, name) = entry.value;
        expect(sizes[entry.key], size, reason: name);
      }
    });

    test('every starter card resolves', () {
      // A starter deck showing a placeholder row would mean the two bundled
      // files were built from different data.
      for (final deck in starters) {
        expect(
          database.card(deck.investigatorCode),
          isNotNull,
          reason: '${deck.name}: investigator ${deck.investigatorCode}',
        );
        for (final code in deck.slots.keys) {
          expect(database.card(code), isNotNull, reason: '${deck.name}: $code');
        }
      }
    });

    test('every starter card has art', () {
      for (final deck in starters) {
        for (final code in deck.slots.keys) {
          expect(
            database.card(code)?.frontImage,
            isNotNull,
            reason: '${deck.name}: $code has no art',
          );
        }
      }
    });

    test('reprint in a starter deck is filled in', () {
      // `60108` is the Core Set's Physical Training and carries nothing but a
      // pointer upstream. The build script fills those in before deriving the
      // deck, so they arrive with a name and a type rather than as blank rows.
      expect(starter('60101').slots['60108'], 2);

      final card = database.card('60108')!;
      expect(card.name, 'Physical Training');
      expect(card.typeCode, 'asset');
      expect(card.duplicateOf, '01017');
    });

    test('upgrade cards are not in the deck', () {
      // This is the whole of the derivation rule, so it is worth stating.
      final deck = starter('60101');
      expect(deck.slots['60120'], isNull, reason: 'Evidence! is level 1');
      expect(deck.slots['60132'], isNull, reason: 'One-Two Punch is level 5');

      for (final code in deck.slots.keys) {
        final card = database.card(code)!;
        expect(card.level, 0, reason: '${card.name} is level ${card.level}');
      }
    });

    test('starter decks are not imported', () {
      expect(starters.every((deck) => !deck.isImported), isTrue);
    });
  });

  group('DeckContents', () {
    test('groups by type in game order', () {
      final contents = DeckContents(starter('60101'), database);

      expect(contents.investigator?.name, 'Nathaniel Cho');
      expect(contents.cardCount, 33);
      expect(contents.unresolvedCodes, isEmpty);

      expect(
        contents.sections.map((section) => section.typeCode).toList(),
        ['asset', 'event', 'skill', 'enemy', 'treachery'],
      );
      expect(
        contents.sections.map((section) => section.cardCount).toList(),
        [13, 16, 2, 1, 1],
      );
    });

    test('sorts by name within a section', () {
      // Cards read in name order within their section, not code order: a deck
      // draws from many boxes and code order interleaves them arbitrarily.
      final contents = DeckContents(starter('60101'), database);
      final assets = contents.sections
          .firstWhere((section) => section.typeCode == 'asset');
      final names = assets.entries.map((entry) => entry.card.name).toList();
      expect(names, [...names]..sort());
    });

    test('paging sequence has no duplicates', () {
      // One page per card, not per copy: paging sideways through two identical
      // pages would be a bug.
      final contents = DeckContents(starter('60101'), database);
      expect(contents.cards.length, 18, reason: 'distinct cards, not 33 copies');
      expect(
        contents.cards.map((card) => card.code).toSet().length,
        contents.cards.length,
      );
    });

    test('paging sequence opens with the investigator', () {
      // More than cosmetic: a sequence of one cannot be paged, and the card
      // view installs its back swipe only where a pager exists, so giving the
      // investigator a sequence of its own left that screen with no way out.
      final contents = DeckContents(starter('60101'), database);
      expect(contents.pageSequence.first.code, '60101');
      expect(contents.pageSequence.length, contents.cards.length + 1);
      expect(
        contents.pageSequence.map((card) => card.code).toSet().length,
        contents.pageSequence.length,
      );
    });

    test('paging sequence omits an unknown investigator', () {
      const deck = Deck(
        source: ImportedSource(2),
        name: 'Unknown investigator',
        investigatorCode: '99999',
        slots: {'01006': 1},
        sideSlots: {},
      );
      final contents = DeckContents(deck, database);
      expect(contents.investigator, isNull);
      expect(contents.pageSequence.map((card) => card.code).toList(), ['01006']);
    });

    test('reports unresolved codes rather than dropping them', () {
      // An imported deck naming a card from a box newer than this app's data
      // must not quietly show 28 of its 33 cards.
      const deck = Deck(
        source: ImportedSource(1),
        name: 'Partly unknown',
        investigatorCode: '01001',
        slots: {'01006': 1, '99999': 2, '01016': 1},
        sideSlots: {},
      );
      final contents = DeckContents(deck, database);
      expect(contents.unresolvedCodes, ['99999']);
      expect(contents.cardCount, 2, reason: 'the two that resolved');
      expect(contents.investigator, isNotNull);
    });

    test('survives an unknown investigator', () {
      const deck = Deck(
        source: ImportedSource(2),
        name: 'Unknown investigator',
        investigatorCode: '99999',
        slots: {'01006': 1},
        sideSlots: {},
      );
      final contents = DeckContents(deck, database);
      expect(contents.investigator, isNull);
      expect(contents.unresolvedCodes, ['99999']);
      expect(contents.cardCount, 1);
    });

    test('keeps the side deck separate', () {
      const deck = Deck(
        source: ImportedSource(3),
        name: 'With a side deck',
        investigatorCode: '01001',
        slots: {'01006': 1},
        sideSlots: {'01016': 2},
      );
      final contents = DeckContents(deck, database);
      expect(contents.cardCount, 1);
      expect(contents.sideCardCount, 2);
      expect(contents.cards.length, 1, reason: 'paging stays in the main deck');
    });

    test('unresolved codes come out in a fixed order', () {
      // The investigator first, then the main deck and the side deck in code
      // order. Without the sort this depends on map iteration.
      const deck = Deck(
        source: ImportedSource(4),
        name: 'Several unknowns',
        investigatorCode: '99999',
        slots: {'99998': 1, '01006': 1, '99997': 1},
        sideSlots: {'99996': 1},
      );
      final contents = DeckContents(deck, database);
      expect(contents.unresolvedCodes, ['99999', '99997', '99998', '99996']);
    });
  });
}
