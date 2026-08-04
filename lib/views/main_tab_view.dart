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
