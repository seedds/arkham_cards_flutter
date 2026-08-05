import 'package:arkham_cards/views/card_detail_view.dart';
import 'package:arkham_cards/views/card_image_view.dart';
import 'package:arkham_cards/views/card_row.dart';
import 'package:arkham_cards/views/card_text.dart';
import 'package:arkham_cards/views/deck_row.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

/// `CardPlaceholder` stands in for a card the TTS mod carries no art for. It was
/// written for the detail screen, which gives it the whole card area, and a row
/// gives it 28pt -- less than the icon and name inside it need, so it overflowed
/// its box and spilled the card's name down the screen. It now sheds what does
/// not fit.
///
/// The detail screen no longer reaches it: a side with no picture goes to
/// `CardText`, which has words or, failing those, the card's printing details.
/// So this is the row thumbnail's widget, and the tests below say so.
///
/// The sizes below are measured, not derived: a landscape row thumbnail is
/// 28x20 but a portrait one is only 20pt *wide*, which is narrower than the 20pt
/// icon plus its 12pt of padding. A height-only threshold still overflowed
/// sideways.
void main() {
  // Rows carry card art, which a widget test has no asset bundle for; what is
  // under test is the artless case, which reaches no bundle at all.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  // Two cards with no front art, one of each orientation -- the distinction
  // that sizes the box. 124 fronts still have no crop -- sides the mod prints
  // as the reverse of another card -- so these are examples, not the only
  // candidates.
  const landscapeCode = '10016a'; // Hank Samson, investigator
  const portraitCode = '09600a'; // Cafe Luna, location

  Future<void> pumpRow(WidgetTester tester, Widget row) => tester.pumpWidget(
    CupertinoApp(
      home: Align(
        alignment: Alignment.topLeft,
        // A real list row's width, so the name has somewhere to wrap to and the
        // overflow is the placeholder's own rather than the harness's.
        child: SizedBox(width: 400, child: row),
      ),
    ),
  );

  group('a row thumbnail', () {
    testWidgets('fits its box for a landscape card', (tester) async {
      await pumpRow(tester, CardRow(card: database.card(landscapeCode)!));

      // 28x20: the square box letterboxes investigator art.
      expect(
        tester.getSize(find.byType(CardPlaceholder)),
        const Size(CardRow.thumbnailSize, CardRow.thumbnailSize / 1.4),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits its box for a portrait card', (tester) async {
      await pumpRow(tester, CardRow(card: database.card(portraitCode)!));

      expect(
        tester.getSize(find.byType(CardPlaceholder)),
        const Size(CardRow.thumbnailSize / 1.4, CardRow.thumbnailSize),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a deck row, which is larger but still small', (
      tester,
    ) async {
      await pumpRow(
        tester,
        DeckRow(
          deck: starters.first,
          investigator: database.card(landscapeCode)!,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('names nothing -- the row prints the name beside it', (
      tester,
    ) async {
      final card = database.card(landscapeCode)!;
      await pumpRow(tester, CardRow(card: card));

      // Once, from the row's own label. Twice would mean the placeholder is
      // still captioning art it is not showing.
      expect(find.text(card.name), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CardPlaceholder),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });
  });

  group('the detail screen', () {
    testWidgets('prints the details for a card with no art and no text', (
      tester,
    ) async {
      // Cafe Luna's front has neither art nor text -- its rules are on the
      // back -- which would otherwise be a name in the navigation bar above an
      // empty screen. `CardText` stands in with what identifies the card, so
      // the placeholder -- whose icon says only "no picture" -- is not what
      // the detail screen shows any more.
      final card = database.card(portraitCode)!;
      expect(card.frontImage, isNull, reason: 'fixture must lack art');
      expect(card.text, isNull, reason: 'fixture must lack text');

      await tester.pumpWidget(
        CupertinoApp(
          home: CardDetailView(card: card, cards: [card], database: database),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CardPlaceholder), findsNothing);
      final details = find.byType(CardText);
      expect(details, findsOneWidget);

      // Twice: the navigation bar names it too, and this is the copy inside the
      // card-shaped box.
      expect(
        find.descendant(of: details, matching: find.text(card.name)),
        findsOneWidget,
      );
      // The box and number, which is what tells this card from its reprints.
      expect(
        find.descendant(
          of: details,
          matching: find.textContaining('#${card.printedNumber}'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeps the icon and the name where there is text to read', (
      tester,
    ) async {
      // A card with text still shows it, so the placeholder is reached only by
      // rows. Pinned so shrinking the row version does not silently blank the
      // detail fallback.
      final card = database.card(landscapeCode)!;
      expect(card.text, isNotNull);

      await tester.pumpWidget(
        CupertinoApp(
          home: CardDetailView(card: card, cards: [card], database: database),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CardText), findsOneWidget);
    });
  });
}
