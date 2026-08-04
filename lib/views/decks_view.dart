import 'package:flutter/cupertino.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../models/card_database.dart';
import '../models/deck.dart';
import '../models/deck_store.dart';
import 'deck_detail_view.dart';
import 'deck_import_view.dart';
import 'deck_row.dart';
import 'launch_options.dart';

/// The decks tab: the ten starters, then whatever has been imported.
class DecksView extends StatefulWidget {
  const DecksView({required this.database, required this.store, super.key});

  final CardDatabase database;
  final DeckStore store;

  @override
  State<DecksView> createState() => _DecksViewState();
}

class _DecksViewState extends State<DecksView> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    // A list row cannot be tapped from a script -- it is absent from the
    // accessibility tree and out of reach of synthesised events -- so the
    // screen to open is named at launch instead.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLaunchScreens());
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() => setState(() {});

  void _openLaunchScreens() {
    if (!mounted) return;
    if (LaunchOptions.sheet == 'import') _openImport();

    final id = LaunchOptions.deck;
    if (id.isEmpty) return;
    final decks = [...widget.store.starters, ...widget.store.imported];
    final match = decks.where((deck) => deck.id == id).firstOrNull;
    if (match != null) _open(match);
  }

  void _open(Deck deck) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (context) =>
          DeckDetailView(deck: deck, database: widget.database),
    ),
  );

  void _openImport() => showCupertinoSheet<void>(
    context: context,
    scrollableBuilder: (context, controller) =>
        DeckImportView(store: widget.store, scrollController: controller),
  );

  @override
  Widget build(BuildContext context) {
    final imported = widget.store.imported;
    final starters = widget.store.starters;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Decks'),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _openImport,
              child: const Icon(
                CupertinoIcons.plus,
                semanticLabel: 'Import a deck',
              ),
            ),
          ),
          // Imported first: they are the decks the user chose to keep, and the
          // ten starters are always there underneath.
          //
          // Hidden entirely when empty: an "Imported" header over nothing
          // invites the question of what is missing.
          if (imported.isNotEmpty)
            SliverToBoxAdapter(
              child: CupertinoListSection.insetGrouped(
                header: const Text('Imported'),
                children: [for (final deck in imported) _deletableRow(deck)],
              ),
            ),
          if (starters.isNotEmpty)
            SliverToBoxAdapter(
              child: CupertinoListSection.insetGrouped(
                header: const Text('Starter Decks'),
                children: [for (final deck in starters) _deletableRow(deck)],
              ),
            ),
          SliverPadding(
            // The tab bar is translucent, so CupertinoTabScaffold reports its
            // 50pt as a MediaQuery padding hint rather than insetting the
            // content. A BoxScrollView consumes that hint; a CustomScrollView
            // does not, so without this the last row sits under the bar.
            padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ],
      ),
    );
  }

  /// A row that swipes to reveal Delete.
  ///
  /// Both sections use it. Deleting a starter only hides it -- Settings has a
  /// row that brings them all back -- so the same red button means something
  /// weaker there than it does over an import, which is the one thing here
  /// that is not reversible.
  Widget _deletableRow(Deck deck) => Slidable(
    key: ValueKey(deck.id),
    endActionPane: ActionPane(
      motion: const DrawerMotion(),
      extentRatio: 0.25,
      children: [
        SlidableAction(
          onPressed: (_) => widget.store.remove(deck),
          backgroundColor: CupertinoColors.destructiveRed,
          foregroundColor: CupertinoColors.white,
          label: 'Delete',
        ),
      ],
    ),
    child: _row(deck),
  );

  Widget _row(Deck deck) => CupertinoListTile.notched(
    onTap: () => _open(deck),
    title: DeckRow(
      deck: deck,
      investigator: widget.database.card(deck.investigatorCode),
    ),
    trailing: const CupertinoListTileChevron(),
  );
}
