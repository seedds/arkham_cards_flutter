import 'package:arkham_cards/views/card_detail_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

/// The card screen hides the navigation bar, so the edge swipe is the only way
/// back -- and it has to survive a full-width pager competing for the same
/// drag. Flutter's route gesture wins that contest on its own, but an edge
/// widget added here later would silently take the swipe away and leave the
/// screen a dead end, which is what these pin.
void main() {
  // Rows carry card art, which a widget test has no asset bundle for; the
  // gesture arithmetic is what is under test, not the pictures.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  Future<void> pumpDetail(
    WidgetTester tester, {
    required List<String> codes,
    required String opensOn,
  }) async {
    final cards = [for (final code in codes) database.card(code)!];
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (context) => CardDetailView(
                  card: database.card(opensOn)!,
                  cards: cards,
                  database: database,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a drag from the leading edge goes back', (tester) async {
    await pumpDetail(tester, codes: ['01001', '01002'], opensOn: '01001');
    expect(find.byType(CardDetailView), findsOneWidget);

    await tester.flingFrom(const Offset(5, 400), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailView), findsNothing);
  });

  testWidgets('a drag from the middle pages instead of going back', (
    tester,
  ) async {
    await pumpDetail(tester, codes: ['01001', '01002'], opensOn: '01001');

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Still on the card screen, and now showing the next card.
    expect(find.byType(CardDetailView), findsOneWidget);
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    expect(controller.page?.round(), 1);
  });

  testWidgets('a leftward drag at the edge does not go back', (tester) async {
    // Paging, not going back -- the same rule the Swift recogniser applied.
    await pumpDetail(tester, codes: ['01001', '01002'], opensOn: '01001');

    await tester.flingFrom(const Offset(5, 400), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailView), findsOneWidget);
  });

  testWidgets('a single card still has a way back', (tester) async {
    // The case that stranded the Swift screen: one page cannot be paged, and
    // the back swipe had been installed only where a pager existed.
    await pumpDetail(tester, codes: ['01001'], opensOn: '01001');

    await tester.flingFrom(const Offset(5, 400), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailView), findsNothing);
  });

  testWidgets('opening a card not in the list shows just that card', (
    tester,
  ) async {
    await pumpDetail(tester, codes: ['01002', '01003'], opensOn: '01001');

    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    expect(controller.initialPage, 0);
    expect(find.byType(PageView), findsOneWidget);
  });
}
