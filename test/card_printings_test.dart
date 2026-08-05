import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

/// Reprints and parallel investigators are separate records pointing back at
/// the original. Grouping them is what ties a card's versions together.
void main() {
  List<String> printings(String code) =>
      database.printings(database.card(code)!).map((card) => card.code).toList();

  group('printings', () {
    test('card printed once returns only itself', () {
      // Most cards are like this: printed once, in one box.
      expect(printings('01104'), ['01104']);
    });

    test('reprints are grouped in release order', () {
      expect(printings('01039'), [
        '01039',
        '01539',
        '12039',
        '60219',
        '60267',
      ]);
    });

    test('every printing has art, shared where the box does not differ', () {
      // Each printing must show something, or the extra rows are blank. They no
      // longer all show something *different*: the art is cropped from the TTS
      // mod, which stocks a card once under its first printing's code, so a
      // reprint the mod has no object for borrows the original's picture. The
      // rows still differ by box and number, which is what they are for.
      final deduction = database.card('01039')!;
      final art = database
          .printings(deduction)
          .map((card) => card.frontImage)
          .toList();
      expect(art.length, 5);
      expect(art, everyElement(isNotNull));
      expect(art.toSet(), contains('01039.webp'));
    });

    test('group is reachable from any printing', () {
      expect(printings('01039'), printings('60267'));
    });

    test('card with both pointers appears once', () {
      // 01501 carries both a duplicate_of and an alternate_of, naming the same
      // original; it must group once, not twice.
      final codes = printings('01001');
      expect(codes.where((code) => code == '01501').length, 1);
      expect(codes, contains('90024'), reason: 'parallel investigator');
    });

    test('promo printing is grouped with the card it reprints', () {
      // Upstream gives `98004` a full standalone record and no pointer, so it
      // grouped alone and was missing from the Core Set Roland's editions. The
      // build script supplies the `alternate_of` link; without it this list is
      // three long.
      expect(printings('01001'), ['01001', '01501', '98004', '90024']);

      // Reachable from the promo too, which is the side the user opens it from.
      expect(printings('98004'), printings('01001'));
    });

    test('every promo printing is linked', () {
      // All 10, so a link dropped from the table fails here rather than
      // showing up as one card quietly missing an edition.
      const expected = {
        '98001': '02003',
        '98004': '01001',
        '98007': '08004',
        '98010': '05001',
        '98013': '07005',
        '98016': '07004',
        '98019': '11014',
        '99001': '05006',
        '99002': '05018',
        '99003': '05019',
      };
      for (final entry in expected.entries) {
        final promo = database.card(entry.key)!;
        expect(promo.alternateOf, entry.value, reason: entry.key);
        expect(
          printings(entry.key),
          contains(entry.value),
          reason: '${entry.key} is not grouped with ${entry.value}',
        );
      }
    });

    test('promo printing keeps its own identity', () {
      // The link must not flatten a promo into the card it reprints: it has its
      // own printed text, illustrator and box, which is why it is a row of its
      // own rather than a duplicate hidden behind the original.
      //
      // Its picture is the one thing it no longer keeps. The TTS mod has no
      // object for `98004`, so the promo Roland borrows the Core Set Roland's
      // art -- the same portrait, which is nearer the truth than the placeholder
      // it would otherwise show.
      final promo = database.card('98004')!;
      final original = database.card('01001')!;

      expect(promo.frontImage, original.frontImage);
      expect(promo.illustrator, 'Brian Valenzuela');
      expect(promo.flavor, isNot(original.flavor));
      expect(promo.packName, 'The Dirge of Reason');

      // Silas Marsh's promo carries a typo the reprint does not, so the link
      // must not copy text over either.
      expect(database.card('98013')!.text, isNot(database.card('07005')!.text));
    });

    test('chained pointers collapse to one group', () {
      // One card points at a card that is itself a reprint; following the
      // pointers must reach the true original rather than stopping halfway.
      for (final card in database.all) {
        final group = database.printings(card);
        expect(group, contains(card),
            reason: '${card.code} is missing from its own group');
        final codes = group.map((member) => member.code).toList();
        for (final member in group) {
          expect(
            database.printings(member).map((card) => card.code).toList(),
            codes,
            reason: '${card.code} and ${member.code} disagree',
          );
        }
      }
    });
  });

  group('variants: several cards at one number in one box', () {
    test('variants at one number are grouped', () {
      // The two `Hunter's Hunger` in Fortune and Folly are one card printed
      // twice with a different suit pip. They listed as two rows nothing could
      // tell apart, which is what `variant_of` and `printedNumber` fix.
      expect(printings('88053a'), ['88053a', '88053b']);
      // Reachable from either side, like a reprint group.
      expect(printings('88053b'), printings('88053a'));

      final clubs = database.card('88053a')!;
      final hearts = database.card('88053b')!;
      // Same name, box and position; only the code's letter separates them,
      // so the row has to show that letter.
      expect(clubs.name, hearts.name);
      expect(clubs.position, hearts.position);
      expect(clubs.printedNumber, '53a');
      expect(hearts.printedNumber, '53b');

      // Each pip is its own picture, or the extra row shows nothing new.
      expect(clubs.frontImage, '88053a.webp');
      expect(hearts.frontImage, '88053b.webp');
    });

    test('far sides of a pair are not treated as variants', () {
      // A shared name, box and position can also mean the two faces of one
      // card. In The Wages of Sin all twelve of `05178a`-`05178l` share
      // position 178: six `Heretic` fronts, each `back_link`ed to an
      // `Unfinished Business` back. The two must stay separate groups, which
      // is the one thing the variant rule exists to do.
      expect(printings('05178a'), [
        '05178a',
        '05178c',
        '05178e',
        '05178g',
        '05178i',
        '05178k',
      ]);
      expect(printings('05178b'), [
        '05178b',
        '05178d',
        '05178f',
        '05178h',
        '05178j',
        '05178l',
      ]);

      // 05178b is 05178a's back, so it must not be in 05178a's group.
      final heretic = database.card('05178a')!;
      expect(heretic.backLink, '05178b');
      expect(database.printings(heretic), isNot(contains(database.card('05178b'))));
    });

    test('variant groups are as expected', () {
      // The totals, so an upstream change to what a shared position means
      // fails here rather than silently merging or splitting rows.
      final variants =
          database.all.where((card) => card.variantOf != null).toList();
      expect(variants.length, 138);
      expect(variants.map((card) => card.variantOf).toSet().length, 51);

      // The largest is Replicating Aberration, nine at one number.
      expect(
        database.all.where((card) => card.variantOf == '89010a').length,
        9,
      );
    });

    test('no card is both a variant and a reprint', () {
      // Variants and reprints are different relations -- a sibling in this box
      // against the same card in a later one. If one card were ever both, the
      // pointer walk would have to choose which wins.
      for (final card in database.all.where((card) => card.variantOf != null)) {
        expect(card.duplicateOf, isNull, reason: card.code);
        expect(card.alternateOf, isNull, reason: card.code);
      }
    });

    test('printed number distinguishes rows within a box', () {
      // What the list actually depends on: no two cards in a box share a
      // printed number *and* a name. 356 rows used to be indistinguishable.
      final seen = <String>{};
      for (final card in database.all) {
        final key = '${card.packCode}|${card.printedNumber}|${card.name}';
        expect(seen.add(key), isTrue, reason: 'duplicate row: $key');
      }
    });

    test('groups cover every card exactly once', () {
      final seen = <String>{};
      for (final card in database.all) {
        final group = database.printings(card);
        if (group.first.code != card.code) continue;
        for (final member in group) {
          expect(seen.add(member.code), isTrue,
              reason: '${member.code} is in two groups');
        }
      }
      expect(seen.length, database.all.length);
    });
  });
}
