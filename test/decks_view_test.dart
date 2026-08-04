import 'dart:io';

import 'package:arkham_cards/models/deck.dart';
import 'package:arkham_cards/models/deck_store.dart';
import 'package:arkham_cards/views/decks_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

/// What the decks tab does that the model tests cannot see: which section
/// comes first, that a starter row swipes at all, and that the last row is not
/// under the tab bar.
void main() {
  // Rows carry card art, which a widget test has no asset bundle for.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late Directory temporary;
  late DeckStore store;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('arkham-decks-view');
    store = DeckStore(
      starters: starters,
      storeFile: File('${temporary.path}/imported-decks.json'),
    );
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  /// The tab bar is not built here, so its 50pt is supplied the way
  /// CupertinoTabScaffold supplies it: as a padding hint the content is
  /// expected to honour itself.
  Future<void> pump(WidgetTester tester) async {
    // An iPhone 17 Pro: 402x874 logical, with the tab bar's 50pt and the home
    // indicator's 34 reported together as CupertinoTabScaffold reports them.
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CupertinoApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 84)),
          child: DecksView(database: database, store: store),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a starter deck swipes to reveal Delete', (tester) async {
    // The swipe was on imported rows only, so a starter row had nothing to
    // reveal and the gesture appeared to do nothing at all.
    await pump(tester);
    expect(find.text('Nathaniel Cho'), findsOneWidget);

    await tester.drag(find.text('Nathaniel Cho'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('deleting a starter hides it and Settings can bring it back', (
    tester,
  ) async {
    await pump(tester);

    await tester.drag(find.text('Nathaniel Cho'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Nathaniel Cho'), findsNothing);
    expect(store.hiddenStarterCount, 1);

    store.restoreStarters();
    await tester.pumpAndSettle();
    expect(find.text('Nathaniel Cho'), findsOneWidget);
  });

  testWidgets('imported decks come before the starters', (tester) async {
    store.add(
      const Deck(
        source: ImportedSource(40838),
        name: 'Rexploding Performance',
        investigatorCode: '02002',
        slots: {'01030': 2},
        sideSlots: {},
      ),
    );
    await pump(tester);

    expect(
      tester.getTopLeft(find.text('Imported')).dy,
      lessThan(tester.getTopLeft(find.text('Starter Decks')).dy),
    );
  });

  testWidgets('the last row scrolls clear of the tab bar', (tester) async {
    // A CustomScrollView does not consume the scaffold's bottom padding hint
    // the way a ListView does, so the trailing sliver has to add it back.
    //
    // Enough imports that the list is long enough to press its last row
    // against the bottom, which is the only arrangement where the missing
    // padding shows. The ten starters alone fit on this screen without
    // scrolling at all.
    for (var id = 1; id <= 12; id++) {
      store.add(
        Deck(
          source: ImportedSource(id),
          name: 'Imported $id',
          investigatorCode: '02002',
          slots: const {'01030': 2},
          sideSlots: const {},
        ),
      );
    }
    await pump(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    // Scrolled fully to the bottom, the gap under the last row has to cover
    // the bar. Asserting on the row's screen position instead would not pin
    // this: the list is short enough that it lands above the bar regardless,
    // and the assertion would hold with the padding removed.
    // The section's own bottom edge, not the last row's text: a row carries
    // padding of its own, which reads as clearance the section does not have
    // and which passes this test with the fix removed.
    final gap =
        tester.getSize(find.byType(DecksView)).height -
        tester.getBottomLeft(find.byType(CupertinoListSection).last).dy;
    expect(gap, greaterThanOrEqualTo(84));
  });
}
