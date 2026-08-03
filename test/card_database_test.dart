import 'package:arkham_cards/models/card.dart';
import 'package:arkham_cards/models/card_database.dart';
import 'package:arkham_cards/models/card_query.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

List<Card> matches(String text) =>
    database.cards(CardQuery(searchText: text));

void main() {
  group('CardDatabase', () {
    test('every card decodes', () {
      expect(database.all.length, 5928);
    });

    test('every record is listed under its own code', () {
      // Reprints and the far halves of two-card pairs used to be filtered out;
      // they are separate cards with their own art, so they get their own row.
      expect(database.all.map((card) => card.code).toSet().length, 5928);
      expect(database.cards(const CardQuery(searchText: '')).length, 5928);
    });

    test('investigator has back and stats', () {
      final roland = database.card('01001')!;
      expect(roland.name, 'Roland Banks');
      expect(roland.factionCode, 'guardian');
      expect(roland.isInvestigator, isTrue);
      expect(roland.isLandscape, isTrue);
      expect(roland.frontImage, '01001.webp');
      expect(roland.backImage, '01001b.webp');
      expect(roland.health?.number, 9);
    });

    test('back link resolves to separate card', () {
      final front = database.card('05217')!;
      final back = database.back(front)!;
      expect(back.code, '05217b');
      expect(back.subname, 'Master of Indoctrination');
    });

    test('card without front image still loads', () {
      final card = database.card('04117a')!;
      expect(card.frontImage, isNull);
      expect(card.backImage, isNotNull);
    });

    test('cards wanting a back image that is not bundled', () {
      // 22 cards say they have a second side but no image of it was bundled.
      // `98004` Roland Banks is one: arkhamdb serves `98004b`, the image source
      // this bundle is built from does not.
      final wantsABack = database.all
          .where(
            (card) =>
                (card.backLink != null || card.doubleSided == true) &&
                card.backImage == null,
          )
          .toList();
      expect(
        wantsABack.length,
        22,
        reason: 'missing: ${wantsABack.take(5).map((card) => card.code)}',
      );

      final roland = database.card('98004')!;
      expect(roland.doubleSided, isTrue);
      expect(roland.backImage, isNull);
      // The front is present, so this is a missing back and not a card
      // without art at all.
      expect(roland.frontImage, '98004.webp');
    });

    test('missing back image falls back to text for sixteen', () {
      // Of those 22, the 16 carrying the back's text flip to it; the 6 with
      // neither picture nor text stay one-sided.
      final wantsABack = database.all
          .where(
            (card) =>
                (card.backLink != null || card.doubleSided == true) &&
                card.backImage == null,
          )
          .toList();
      final withText =
          wantsABack.where((card) => card.backText != null).toList();
      expect(withText.length, 16);
      expect(wantsABack.length - withText.length, 6);

      // Roland flips to his deckbuilding rules.
      final roland = database.card('98004')!;
      expect(roland.hasBack, isTrue);
      expect(roland.backText, isNotNull);

      // The Organist has neither, so there is nothing to turn over to.
      final organist = database.card('03221b')!;
      expect(organist.backImage, isNull);
      expect(organist.backText, isNull);
      expect(organist.hasBack, isFalse);
    });

    test('traits and skills', () {
      final card = database.card('01006')!;
      expect(card.traits, 'Item. Weapon. Firearm.');
      expect(card.skillCombat?.number, 1);
    });

    test('search matches name only', () {
      expect(matches('shotgun').any((card) => card.code == '01029'), isTrue);
      expect(matches('roland').any((card) => card.code == '01001'), isTrue);
      // Every needle must be in the name, so extra words narrow.
      expect(
        matches('shotgun tome').any((card) => card.code == '01029'),
        isFalse,
      );
    });

    test('search ignores traits and subname', () {
      // No card is named "Firearm", and "The Fed" is Roland's subname rather
      // than his name.
      expect(matches('firearm').any((card) => card.code == '01029'), isFalse);
      expect(matches('the fed').any((card) => card.code == '01001'), isFalse);
    });

    test('search returns every printing of a card', () {
      final codes = matches('roland banks').map((card) => card.code).toSet();
      expect(codes, containsAll(['01001', '01501', '90024']));
    });

    test('search ignores case and accents', () {
      expect(
        matches('SHOTGUN').map((card) => card.code).toList(),
        matches('shotgun').map((card) => card.code).toList(),
      );
      // The fold strips a combining mark but leaves a ligature alone. Both
      // halves are pinned, so the hand-written table cannot drift in either
      // direction -- into transliterating `œ`, or out of stripping accents.
      expect(CardDatabase.fold('Luís'), 'luis');
      expect(CardDatabase.fold('André'), 'andre');
      expect(CardDatabase.fold('Chœur'), 'chœur');
      expect(matches('choeur'), isEmpty);
      expect(matches('chœur').any((card) => card.code == '03292'), isTrue);
    });

    test('filtering by faction and level', () {
      final results = database.cards(
        const CardQuery(factions: {'guardian'}, levels: {0}),
      );
      expect(results, isNotEmpty);
      expect(
        results.every((card) => card.factions.contains('guardian')),
        isTrue,
      );
      expect(results.every((card) => card.level == 0), isTrue);
    });

    test('player and encounter partition the set', () {
      final total =
          database.cards(const CardQuery(deck: DeckKind.player)).length +
          database.cards(const CardQuery(deck: DeckKind.encounter)).length;
      expect(total, database.all.length);
    });

    test('filter options are ordered and present', () {
      expect(database.factions.first, 'guardian');
      expect(database.types.first, 'investigator');
      expect(database.levels, [0, 1, 2, 3, 4, 5]);
      expect(database.cycles, isNotEmpty);
    });

    test('count matches the list it would produce', () {
      // The filter sheet counts and the list filters through the same
      // predicate; if they ever diverge the sheet promises the wrong number.
      const queries = [
        CardQuery(),
        CardQuery(factions: {'survivor'}),
        CardQuery(searchText: 'shotgun'),
      ];
      for (final query in queries) {
        expect(database.count(query), database.cards(query).length);
      }
    });

    test('cycle name falls back to the code', () {
      final cycle = database.cycles.first;
      expect(database.cycleName(cycle.code), cycle.name);
      expect(database.cycleName('no_such_cycle'), 'no_such_cycle');
    });

    test('active filter count', () {
      var query = const CardQuery();
      expect(query.isFiltered, isFalse);
      query = query.copyWith(
        factions: {'rogue', 'mystic'},
        deck: DeckKind.player,
      );
      // Each selected class counts individually; the deck filter counts once.
      expect(query.activeFilterCount, 3);
      expect(query.cleared().isFiltered, isFalse);
    });

    test('clearing filters keeps the search text', () {
      const query = CardQuery(searchText: 'shotgun', factions: {'rogue'});
      expect(query.cleared().searchText, 'shotgun');
      expect(query.cleared().factions, isEmpty);
    });
  });

  group('CardValue', () {
    test('sentinels', () {
      CardValue decode(Object? json) => CardValue.fromJson(json);

      expect(decode(3), const CardNumber(3));
      expect(decode(-2), const CardVariable());
      expect(decode(-3), const CardStarred());
      expect(decode(-4), const CardUnknown());
      expect(decode(null), const CardDash());
      expect(decode(-2).display, 'X');
      // -1 is not a sentinel.
      expect(decode(-1), const CardNumber(-1));
    });

    test('an absent key is not a printed dash', () {
      // Three states, not two: no key means the field is not printed on this
      // card, a null means a printed dash, and a number means a number.
      expect(Card.readValue(const {}, 'shroud'), isNull);
      expect(Card.readValue(const {'shroud': null}, 'shroud'),
          const CardDash());
      expect(Card.readValue(const {'shroud': 2}, 'shroud'), const CardNumber(2));
    });
  });

  group('sorting', () {
    List<Card> sorted([CardQuery query = const CardQuery()]) =>
        database.cards(query, sort: CardSort.name);

    test('the default is the bundled order, untouched', () {
      // The cycle list is derived by walking `all`, so sorting must be opt-in.
      final bundled = database.all.map((card) => card.code);
      expect(
        database.cards(const CardQuery()).map((card) => card.code),
        orderedEquals(bundled),
      );
      expect(
        database
            .cards(const CardQuery(), sort: CardSort.release)
            .map((card) => card.code),
        orderedEquals(bundled),
      );
    });

    test('an accent sorts under its base letter', () {
      // Dart compares code units, so a raw compare puts the two `Zócalo`
      // (U+00F3) after `Zulan-Thek` and at the very end of the list.
      final names = sorted().map((card) => card.name).toList();
      final zocalo = names.indexOf('Zócalo');
      expect(zocalo, greaterThan(-1));
      expect(names.indexOf('Zoog Burrow'), greaterThan(zocalo));
      expect(names.last, isNot('Zócalo'));
    });

    test('case does not decide the order', () {
      // Folding lowercases, so the sort is the one the search field implies.
      // A raw compare puts `Abandoned Camp` first, because `C` is 0x43 and the
      // `a` of `and` is 0x61.
      final names = sorted().map((card) => card.name).toList();
      expect(
        names.indexOf('Abandoned and Alone'),
        lessThan(names.indexOf('Abandoned Camp')),
      );

      // And the whole list is non-decreasing on the folded name, not just
      // that pair.
      final folded = [for (final name in names) CardDatabase.fold(name)];
      expect(folded, orderedEquals([...folded]..sort()));
    });

    test('same-named cards fall into release order', () {
      // Six `Heretic` share a sort key in The Wages of Sin and two more are
      // reprinted in a later box; the later box must come last.
      final heretics = [
        for (final card in sorted())
          if (card.name == 'Heretic') card.code,
      ];
      expect(heretics, [
        '05178a', '05178c', '05178e', '05178g', '05178i', '05178k',
        '54038', '54039',
      ]);
    });

    test('the order is total, so it does not depend on the input order', () {
      // `List.sort` is unstable and hundreds of cards share a name, so without
      // a tiebreak the same query could come out two different ways.
      final forwards = sorted().map((card) => card.code).toList();
      final backwards = database.all.reversed.toList();
      final again = CardDatabase(backwards)
          .cards(const CardQuery(), sort: CardSort.name)
          .map((card) => card.code)
          .toList();
      expect(again, forwards);
    });

    test('sorting reorders a result without changing what is in it', () {
      const query = CardQuery(factions: {'mystic'}, types: {'asset'});
      final byRelease = database.cards(query);
      final byName = database.cards(query, sort: CardSort.name);
      expect(byName.length, byRelease.length);
      expect(
        byName.map((card) => card.code).toSet(),
        byRelease.map((card) => card.code).toSet(),
      );
      // The count is order-independent, so the filter sheet is unaffected.
      expect(database.count(query), byName.length);
    });
  });

  group('card sides', () {
    test('sides of a linked pair are distinct cards', () {
      // The two sides of a `back_link` pair are different cards, so a side
      // with no bundled art must show a placeholder rather than borrow the
      // other's picture.
      final front = database.card('05217')!;
      final back = database.back(front)!;

      expect(front.frontImage, isNull,
          reason: 'fixture assumes this side has no art');
      expect(front.subname, isNot(back.subname));
      expect(front.enemyFight?.number, isNot(back.enemyFight?.number));
    });
  });
}
