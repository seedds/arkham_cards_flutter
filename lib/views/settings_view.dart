import 'package:flutter/cupertino.dart';

import '../models/card_database.dart';
import '../models/deck_store.dart';
import 'number_format.dart';
import 'theme.dart';

/// Appearance, plus what the app is and what is in it.
///
/// Appearance is the only thing to configure: the app has no account and syncs
/// nothing. The card data carries no version of its own either -- `cards.json`
/// is a bare array and neither upstream source is version-pinned -- so the rest
/// reports what can actually be counted.
class SettingsView extends StatefulWidget {
  const SettingsView({
    required this.database,
    required this.deckStore,
    required this.themeController,
    super.key,
  });

  static const appVersion = '1.0 (1)';

  final CardDatabase database;
  final DeckStore deckStore;
  final ThemeController themeController;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  @override
  void initState() {
    super.initState();
    // Deleting a starter happens on the decks tab, so the hidden count can
    // change while this screen is built but not visible.
    widget.deckStore.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.deckStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() => setState(() {});

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    ),
    child: CustomScrollView(
      slivers: [
        const CupertinoSliverNavigationBar(largeTitle: Text('Settings')),
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('Appearance'),
            children: [
              CupertinoListTile.notched(
                title: const Text('Theme'),
                additionalInfo: Text(widget.themeController.theme.label),
                trailing: const CupertinoListTileChevron(),
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (context) =>
                        _ThemePicker(controller: widget.themeController),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('Decks'),
            footer: const Text(
              'Deleting a starter deck only hides it. Restoring brings back '
              'every one that has been hidden. Imported decks are not '
              'affected, and deleting one of those cannot be undone.',
            ),
            children: [_RestoreStartersTile(store: widget.deckStore)],
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('Cards'),
            children: [
              CupertinoListTile.notched(
                title: const Text('Cards'),
                additionalInfo: Text(grouped(widget.database.all.length)),
              ),
              CupertinoListTile.notched(
                title: const Text('Cycles'),
                additionalInfo: Text('${widget.database.cycles.length}'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('About'),
            footer: const Text(
              'Every card, image and starter deck is bundled with the app and '
              'works offline. Importing a deck is the one thing that reaches '
              'the network: it fetches a published decklist from arkhamdb and '
              'saves it on this device.',
            ),
            children: const [
              CupertinoListTile.notched(
                title: Text('Version'),
                additionalInfo: Text(SettingsView.appVersion),
              ),
            ],
          ),
        ),
        SliverPadding(
          // See DecksView: a CustomScrollView does not consume the tab bar's
          // padding hint, so the last section would sit under the bar.
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    ),
  );
}

/// Brings hidden starter decks back.
///
/// Always shown, and disabled at zero rather than absent: a deletion the user
/// has to already know is undoable, to go looking for the undo, is not much of
/// an undo. Reading "0 hidden" before deleting anything is what makes the
/// swipe on a starter safe to try.
class _RestoreStartersTile extends StatelessWidget {
  const _RestoreStartersTile({required this.store});

  final DeckStore store;

  @override
  Widget build(BuildContext context) {
    final hidden = store.hiddenStarterCount;
    final enabled = hidden > 0;

    return CupertinoListTile.notched(
      title: Text(
        'Restore Starter Decks',
        style: TextStyle(
          color: enabled
              ? CupertinoColors.label.resolveFrom(context)
              : CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      ),
      additionalInfo: Text(hidden == 1 ? '1 hidden' : '$hidden hidden'),
      onTap: enabled ? () => store.restoreStarters() : null,
    );
  }
}

class _ThemePicker extends StatefulWidget {
  const _ThemePicker({required this.controller});

  final ThemeController controller;

  @override
  State<_ThemePicker> createState() => _ThemePickerState();
}

class _ThemePickerState extends State<_ThemePicker> {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    ),
    navigationBar: const CupertinoNavigationBar(middle: Text('Theme')),
    child: SafeArea(
      child: ListView(
        children: [
          CupertinoListSection.insetGrouped(
            children: [
              for (final theme in Theme.values)
                CupertinoListTile.notched(
                  title: Text(theme.label),
                  onTap: () {
                    widget.controller.theme = theme;
                    setState(() {});
                  },
                  trailing: widget.controller.theme == theme
                      ? Icon(
                          CupertinoIcons.check_mark,
                          size: 20,
                          color: CupertinoTheme.of(context).primaryColor,
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
