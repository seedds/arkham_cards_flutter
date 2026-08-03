import 'package:flutter/cupertino.dart';

import '../models/card_database.dart';
import '../models/card_query.dart';
import '../models/type_names.dart';
import 'faction_style.dart';
import 'number_format.dart';

/// The filter sheet: class, type, level, cycle and which deck a card is from.
///
/// Edits a draft and hands it back on dismissal, so the list behind does not
/// rearrange while the sheet is open. Apply and a swipe down do the same thing;
/// there is deliberately no cancel.
class FilterView extends StatefulWidget {
  const FilterView({
    required this.database,
    required this.query,
    this.scrollController,
    super.key,
  });

  final CardDatabase database;
  final CardQuery query;

  /// The sheet's own controller, so dragging this form down dismisses it.
  final ScrollController? scrollController;

  @override
  State<FilterView> createState() => _FilterViewState();
}

class _FilterViewState extends State<FilterView> {
  late CardQuery _draft = widget.query;

  void _update(CardQuery query) => setState(() => _draft = query);

  @override
  Widget build(BuildContext context) {
    // Counted against the draft, so the sheet says what the list is about to
    // become. Includes the search text, which is still in force.
    final count = widget.database.count(_draft);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_draft);
      },
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
          context,
        ),
        navigationBar: CupertinoNavigationBar(
          automaticallyImplyLeading: false,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            // Empties the form without emptying the list behind it, since the
            // edits are staged.
            onPressed: _draft.isFiltered
                ? () => _update(_draft.cleared())
                : null,
            child: const Text('Reset'),
          ),
          middle: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filters'),
              Text(
                count == 1 ? '1 card' : '${grouped(count)} cards',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => Navigator.of(context).pop(_draft),
            child: const Text(
              'Apply',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        child: SafeArea(
          child: ListView(
            controller: widget.scrollController,
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('Deck'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<DeckKind>(
                        groupValue: _draft.deck,
                        onValueChanged: (deck) {
                          if (deck != null) {
                            _update(_draft.copyWith(deck: deck));
                          }
                        },
                        children: {
                          for (final kind in DeckKind.values)
                            kind: Text(kind.label),
                        },
                      ),
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                children: [
                  _CategoryRow<String>(
                    title: 'Class',
                    options: widget.database.factions,
                    selection: _draft.factions,
                    nameOf: FactionStyle.name,
                    colorOf: FactionStyle.color,
                    onChanged: (selection) =>
                        _update(_draft.copyWith(factions: selection)),
                  ),
                  _CategoryRow<String>(
                    title: 'Type',
                    options: widget.database.types,
                    selection: _draft.types,
                    nameOf: typeName,
                    onChanged: (selection) =>
                        _update(_draft.copyWith(types: selection)),
                  ),
                  _CategoryRow<int>(
                    title: 'Level',
                    options: widget.database.levels,
                    selection: _draft.levels,
                    nameOf: (level) => '$level',
                    onChanged: (selection) =>
                        _update(_draft.copyWith(levels: selection)),
                  ),
                  _CategoryRow<String>(
                    title: 'Cycle',
                    options: [
                      for (final cycle in widget.database.cycles) cycle.code,
                    ],
                    selection: _draft.cycles,
                    nameOf: widget.database.cycleName,
                    onChanged: (selection) =>
                        _update(_draft.copyWith(cycles: selection)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One category, summarising its selection and pushing a list to change it.
class _CategoryRow<T extends Object> extends StatelessWidget {
  const _CategoryRow({
    required this.title,
    required this.options,
    required this.selection,
    required this.nameOf,
    required this.onChanged,
    this.colorOf,
    super.key,
  });

  final String title;
  final List<T> options;
  final Set<T> selection;
  final String Function(T) nameOf;
  final Color Function(T, BuildContext)? colorOf;
  final void Function(Set<T>) onChanged;

  /// Filtered from the ordered options rather than mapped from the set, so the
  /// summary always reads in canonical order: "Guardian, Seeker", never the
  /// other way round.
  String get _summary => selection.isEmpty
      ? 'Any'
      : options.where(selection.contains).map(nameOf).join(', ');

  @override
  Widget build(BuildContext context) => CupertinoListTile.notched(
    title: Text(title),
    additionalInfo: Text(
      _summary,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const CupertinoListTileChevron(),
    onTap: () => Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => _OptionList<T>(
          title: title,
          options: options,
          selection: selection,
          nameOf: nameOf,
          colorOf: colorOf,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

/// The options of one category, multi-selected by tapping.
class _OptionList<T extends Object> extends StatefulWidget {
  const _OptionList({
    required this.title,
    required this.options,
    required this.selection,
    required this.nameOf,
    required this.colorOf,
    required this.onChanged,
    super.key,
  });

  final String title;
  final List<T> options;
  final Set<T> selection;
  final String Function(T) nameOf;
  final Color Function(T, BuildContext)? colorOf;
  final void Function(Set<T>) onChanged;

  @override
  State<_OptionList<T>> createState() => _OptionListState<T>();
}

class _OptionListState<T extends Object> extends State<_OptionList<T>> {
  late final Set<T> _selection = {...widget.selection};

  void _toggle(T option) {
    setState(() {
      if (!_selection.remove(option)) _selection.add(option);
    });
    // Reported as it changes rather than on the way back, so the count in the
    // sheet's title moves while this screen is still open.
    widget.onChanged({..._selection});
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    ),
    navigationBar: CupertinoNavigationBar(middle: Text(widget.title)),
    child: SafeArea(
      child: ListView(
        children: [
          CupertinoListSection.insetGrouped(
            children: [
              for (final option in widget.options)
                CupertinoListTile.notched(
                  onTap: () => _toggle(option),
                  leading: widget.colorOf == null
                      ? null
                      : Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.colorOf!(option, context),
                          ),
                        ),
                  title: Text(widget.nameOf(option)),
                  trailing: _selection.contains(option)
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
