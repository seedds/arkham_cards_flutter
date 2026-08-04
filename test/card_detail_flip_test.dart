import 'package:arkham_cards/views/card_back_text.dart';
import 'package:arkham_cards/views/card_detail_view.dart';
import 'package:arkham_cards/views/card_image_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

/// A two-sided card turns over two ways: the bar's flip button and a tap on the
/// art. Neither is the only one, so removing either would leave the tests green
/// if only one were pinned -- both are here for the same reason both ways back
/// are pinned in `card_detail_gesture_test.dart`.
///
/// Which side is showing lives on the screen rather than on the printing widget,
/// because the button drives it from three levels up. That hoist put two things
/// within reach of a regression, and both are pinned below: paging resets to the
/// front, and so does choosing another version.
void main() {
  // Rows carry card art, which a widget test has no asset bundle for; what is
  // under test is which filename is asked for, not the pictures.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<void> pumpDetail(
    WidgetTester tester, {
    required List<String> codes,
    String? opensOn,
  }) async {
    final cards = [for (final code in codes) database.card(code)!];
    await tester.pumpWidget(
      CupertinoApp(
        home: CardDetailView(
          card: database.card(opensOn ?? codes.first)!,
          cards: cards,
          database: database,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Which art the screen is asking for. Rows only ever pass `frontImage`, so a
  /// `b.webp` here is unambiguously the detail screen showing a back.
  String? shownImage(WidgetTester tester) => tester
      .widget<CardImageView>(
        find
            .descendant(
              of: find.byType(PageView),
              matching: find.byType(CardImageView),
            )
            .first,
      )
      .filename;

  // A function, not a final: `bySemanticsLabel` reads the binding, which does
  // not exist until a test starts.
  Finder flipButton() => find.bySemanticsLabel('Turn the card over');

  group('the flip button', () {
    testWidgets('is in the bar for a two-sided card', (tester) async {
      // Roland Banks, front 01001.webp and back 01001b.webp.
      await pumpDetail(tester, codes: ['01001']);

      expect(flipButton(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CupertinoNavigationBar),
          matching: flipButton(),
        ),
        findsOneWidget,
        reason: 'the button belongs in the navigation bar',
      );
    });

    testWidgets('is absent for a one-sided card', (tester) async {
      // Roland's .38 Special: no back image and no back text, so nothing to
      // turn over. 3,691 of the 5,928 cards are like this.
      await pumpDetail(tester, codes: ['01006']);

      expect(flipButton(), findsNothing);
    });

    testWidgets('turns the card over, and back', (tester) async {
      await pumpDetail(tester, codes: ['01001']);
      expect(shownImage(tester), '01001.webp');

      await tester.tap(flipButton());
      await tester.pumpAndSettle();
      expect(shownImage(tester), '01001b.webp');

      // The same button turns it back: it is a toggle, not a one-way trip.
      await tester.tap(flipButton());
      await tester.pumpAndSettle();
      expect(shownImage(tester), '01001.webp');
    });

    testWidgets('shows the back as text where there is no back picture', (
      tester,
    ) async {
      // 98004, the Roland Banks promo: one of the 16 cards whose back exists in
      // the data but not as a picture.
      final promo = database.card('98004')!;
      expect(promo.backImage, isNull, reason: 'fixture must have no back art');
      expect(promo.backText, isNotNull);

      await pumpDetail(tester, codes: ['98004']);
      expect(find.byType(CardBackText), findsNothing);

      await tester.tap(flipButton());
      await tester.pumpAndSettle();

      expect(find.byType(CardBackText), findsOneWidget);
    });

    testWidgets('appears and disappears as the pager moves', (tester) async {
      // Paging from a two-sided card to a one-sided one. The button's presence
      // follows the card on show, not the card the screen opened on.
      await pumpDetail(tester, codes: ['01001', '01006']);
      expect(flipButton(), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(flipButton(), findsNothing);
    });

    testWidgets('paging away from a flipped card shows the next front', (
      tester,
    ) async {
      // Both are two-sided, so the button survives the swipe and only the side
      // should reset.
      await pumpDetail(tester, codes: ['01001', '01002']);
      await tester.tap(flipButton());
      await tester.pumpAndSettle();
      expect(shownImage(tester), '01001b.webp');

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(shownImage(tester), '01002.webp');
    });
  });

  group('a tap on the art', () {
    testWidgets('still turns the card over', (tester) async {
      // The button is an addition, not a replacement.
      await pumpDetail(tester, codes: ['01001']);
      expect(shownImage(tester), '01001.webp');

      await tester.tap(find.byType(CardImageView).first);
      await tester.pumpAndSettle();

      expect(shownImage(tester), '01001b.webp');
    });

    testWidgets('and the bar button share one state', (tester) async {
      // Turned over by tap, turned back by the button: two controls over one
      // flag, not two flags that could disagree.
      await pumpDetail(tester, codes: ['01001']);

      await tester.tap(find.byType(CardImageView).first);
      await tester.pumpAndSettle();
      expect(shownImage(tester), '01001b.webp');

      await tester.tap(flipButton());
      await tester.pumpAndSettle();
      expect(shownImage(tester), '01001.webp');
    });
  });

  testWidgets('choosing another version shows its front', (tester) async {
    // Roland Banks has four printings. Flipped to the Core Set back, tapping
    // the Revised Core row must show 01501's front, not its back: the side is
    // not a property the new version inherits.
    await pumpDetail(tester, codes: ['01001']);
    final reprint = database.card('01501')!;
    expect(reprint.backImage, '01501b.webp', reason: 'fixture has back art');

    await tester.tap(flipButton());
    await tester.pumpAndSettle();
    expect(shownImage(tester), '01001b.webp');

    // The version picker's row for 01501, found by the art its thumbnail asks
    // for, which is the only thing telling the four same-named rows apart.
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is CardImageView && widget.filename == '01501.webp',
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(shownImage(tester), '01501.webp');
  });
}
