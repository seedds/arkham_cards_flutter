import 'package:flutter/cupertino.dart';

import '../models/card_database.dart';
import '../models/deck_store.dart';
import 'card_list_view.dart';
import 'decks_view.dart';
import 'launch_options.dart';
import 'settings_view.dart';
import 'theme.dart';

/// The three tabs.
///
/// The deck store is owned above this, so an import in flight survives
/// switching tabs away and back. The filter is a sheet over the cards tab
/// rather than a fourth tab, so the query and its results live in
/// [CardListView].
class MainTabView extends StatelessWidget {
  const MainTabView({
    required this.database,
    required this.deckStore,
    required this.themeController,
    super.key,
  });

  final CardDatabase database;
  final DeckStore deckStore;
  final ThemeController themeController;

  static int get _initialTab => switch (LaunchOptions.tab) {
    'decks' => 1,
    'settings' => 2,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) => CupertinoTabScaffold(
    controller: CupertinoTabController(initialIndex: _initialTab),
    tabBar: CupertinoTabBar(
      // Ten above the stock 50, because at 50 the icons sit 2pt under the top
      // hairline and the whole cluster reads as pinned to it. The extra all
      // lands above the icon: a tab item is a column of an Expanded icon over
      // the label, so the icon takes every bit of slack and the label stays
      // 4pt above the bottom inset wherever the top edge goes.
      //
      // The 34pt below the label is the home indicator's safe area, which the
      // bar pads out but must not draw into, so the cluster still sits high in
      // the painted box by design. That gap is not something to tune away.
      height: 60,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.square_stack),
          label: 'Cards',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.square_stack_3d_up),
          label: 'Decks',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.gear_alt),
          label: 'Settings',
        ),
      ],
    ),
    tabBuilder: (context, index) => CupertinoTabView(
      builder: (context) => switch (index) {
        0 => CardListView(database: database),
        1 => DecksView(database: database, store: deckStore),
        _ => SettingsView(
          database: database,
          deckStore: deckStore,
          themeController: themeController,
        ),
      },
    ),
  );
}
