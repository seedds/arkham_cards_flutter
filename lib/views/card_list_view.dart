import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import '../models/card_database.dart';
import '../models/card_query.dart';
import 'card_detail_view.dart';
import 'card_row.dart';
import 'filter_view.dart';
import 'launch_options.dart';
import 'number_format.dart';

/// The browse list: every card, narrowed by the search field and the filter
/// sheet. Owns the query and the results it produces.
class CardListView extends StatefulWidget {
  const CardListView({required this.database, super.key});

  final CardDatabase database;

  @override
  State<CardListView> createState() => _CardListViewState();
}

class _CardListViewState extends State<CardListView> {
  final _searchController = TextEditingController();
  CardQuery _query = const CardQuery();
  late List<model.Card> _results = widget.database.all;

  @override
  void initState() {
    super.initState();
    // A list row cannot be tapped from a script, so the card to open is named
    // at launch instead. Same reason as ARKHAM_DECK.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (LaunchOptions.sheet == 'filter') _openFilter();
      final card = widget.database.card(LaunchOptions.card);
      if (card != null) _open(card);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(model.Card card) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (context) => CardDetailView(
        card: card,
        cards: _results,
        database: widget.database,
      ),
    ),
  );

  void _apply(CardQuery query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _results = widget.database.cards(query);
    });
  }

  Future<void> _openFilter() async {
    // The sheet edits a draft, so the list underneath does not rearrange while
    // it is open. Dismissing commits it: there is no cancel, and swiping the
    // sheet down loses nothing.
    final edited = await showCupertinoSheet<CardQuery>(
      context: context,
      // The sheet's scroll controller is handed to the form inside it, so
      // dragging the list down at its top dismisses the sheet as it does
      // everywhere else in iOS.
      scrollableBuilder: (context, controller) => FilterView(
        database: widget.database,
        query: _query,
        scrollController: controller,
      ),
    );
    if (edited != null) _apply(edited);
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchController.text.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            // Inline rather than large: the search field is pinned below it and
            // a large title would push the first row off a short screen.
            largeTitle: Text(
              _results.isEmpty ? 'Cards' : '${grouped(_results.length)} Cards',
            ),
            bottomMode: NavigationBarBottomMode.always,
            stretch: false,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _openFilter,
              child: Icon(
                _query.isFiltered
                    ? CupertinoIcons.line_horizontal_3_decrease_circle_fill
                    : CupertinoIcons.line_horizontal_3_decrease_circle,
                semanticLabel: 'Filter',
              ),
            ),
            // Pinned rather than collapsing, so the field the user is typing
            // into cannot scroll away underneath them.
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: 'Card name',
                  onChanged: (text) =>
                      _apply(_query.copyWith(searchText: text)),
                ),
              ),
            ),
          ),
          if (_results.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                isFiltered: _query.isFiltered,
                isSearching: isSearching,
                onClear: () => _apply(_query.cleared()),
              ),
            )
          else
            SliverList.separated(
              itemCount: _results.length,
              // Inset to where the text starts, as a plain list does, rather
              // than running under the thumbnail.
              separatorBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Container(
                  height: 1 / MediaQuery.devicePixelRatioOf(context),
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
              ),
              itemBuilder: (context, index) {
                final card = _results[index];
                return _CardListRow(card: card, onTap: () => _open(card));
              },
            ),
        ],
      ),
    );
  }
}

/// One tappable row.
///
/// The insets are tight on purpose: at the default a 28pt thumbnail sits in a
/// 60pt row, and the list reads as a third empty.
class _CardListRow extends StatelessWidget {
  const _CardListRow({required this.card, required this.onTap});

  final model.Card card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      // The declared insets are 4pt, but a SwiftUI row also enforces a minimum
      // height, which puts the real gap at nearer 9. Measured against the
      // original rather than guessed: without it the rows are 10pt tighter.
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        children: [
          Expanded(child: CardRow(card: card)),
          const SizedBox(width: 8),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 14,
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isFiltered,
    required this.isSearching,
    required this.onClear,
  });

  final bool isFiltered;
  final bool isSearching;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.search,
            size: 52,
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
          ),
          const SizedBox(height: 12),
          Text(
            'No cards',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltered || isSearching
                ? 'No card matches this search.'
                : 'The card database is empty.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          // Offered only when a filter is the thing hiding the cards. Search
          // text is already visible in the field, and clearing it is obvious.
          if (isFiltered) ...[
            const SizedBox(height: 12),
            CupertinoButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ],
      ),
    ),
  );
}
