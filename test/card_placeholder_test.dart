import 'package:arkham_cards/views/card_detail_view.dart';
import 'package:arkham_cards/views/card_image_view.dart';
import 'package:arkham_cards/views/card_row.dart';
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
/// The sizes below are measured, not derived: a landscape row thumbnail is
/// 28x20 but a portrait one is only 20pt *wide*, which is narrower than the 20pt
/// icon plus its 12pt of padding. A height-only threshold still overflowed
/// sideways.
void main() {
  // Rows carry card art, which a widget test has no asset bundle for; what is
  // under test is the artless case, which reaches no bundle at all.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  // The only two cards with neither front art nor text, so the only two whose
  // rows render a placeholder from real bundled data. One of each orientation,
  // which is the distinction that sizes the box.
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
    testWidgets('keeps the icon and the name', (tester) async {
      // The full placeholder is 768x548 here, far above any threshold. Pinned so
      // shrinking the row version does not silently blank the one place the
      // icon and name are wanted.
      final card = database.card(portraitCode)!;
      await tester.pumpWidget(
        CupertinoApp(
          home: CardDetailView(card: card, cards: [card], database: database),
        ),
      );
      await tester.pumpAndSettle();

      final placeholder = find.byType(CardPlaceholder);
      expect(placeholder, findsOneWidget);
      expect(
        find.descendant(of: placeholder, matching: find.text(card.name)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: placeholder,
          matching: find.byIcon(CupertinoIcons.photo),
        ),
        findsOneWidget,
      );
    });
  });
}
