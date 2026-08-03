import 'card.dart';

/// Whether a card belongs to a player's deck or to the encounter deck.
enum DeckKind {
  any('All'),
  player('Player'),
  encounter('Encounter');

  const DeckKind(this.label);

  final String label;
}

/// What the user is filtering by.
///
/// Every field defaults to no opinion, so a fresh query matches every card.
/// An empty set means "no constraint", never "match nothing" -- the filter
/// screen offers no way to ask for zero cards and this should not invent one.
class CardQuery {
  const CardQuery({
    this.searchText = '',
    this.factions = const {},
    this.types = const {},
    this.cycles = const {},
    this.levels = const {},
    this.deck = DeckKind.any,
  });

  final String searchText;
  final Set<String> factions;
  final Set<String> types;
  final Set<String> cycles;
  final Set<int> levels;
  final DeckKind deck;

  CardQuery copyWith({
    String? searchText,
    Set<String>? factions,
    Set<String>? types,
    Set<String>? cycles,
    Set<int>? levels,
    DeckKind? deck,
  }) => CardQuery(
    searchText: searchText ?? this.searchText,
    factions: factions ?? this.factions,
    types: types ?? this.types,
    cycles: cycles ?? this.cycles,
    levels: levels ?? this.levels,
    deck: deck ?? this.deck,
  );

  bool matches(Card card) {
    // A multi-class card matches if any of its 1-3 classes is selected, which
    // is why this tests the card's classes against the selection rather than
    // the other way round like the scalar filters below.
    if (factions.isNotEmpty && !card.factions.any(factions.contains)) {
      return false;
    }
    if (types.isNotEmpty && !types.contains(card.typeCode)) return false;
    if (cycles.isNotEmpty && !cycles.contains(card.cycleCode)) return false;
    if (levels.isNotEmpty && !levels.contains(card.level)) return false;
    switch (deck) {
      case DeckKind.any:
        break;
      case DeckKind.player:
        if (!card.isPlayerCard) return false;
      case DeckKind.encounter:
        if (card.isPlayerCard) return false;
    }
    return true;
  }

  /// How many filters are on, for the filter button. The search field is
  /// excluded because it is already visible.
  int get activeFilterCount =>
      factions.length +
      types.length +
      cycles.length +
      levels.length +
      (deck == DeckKind.any ? 0 : 1);

  bool get isFiltered => activeFilterCount > 0;

  /// Clears the filters but not the search text, which the field still shows.
  CardQuery cleared() => CardQuery(searchText: searchText);

  @override
  bool operator ==(Object other) =>
      other is CardQuery &&
      other.searchText == searchText &&
      other.deck == deck &&
      _setEquals(other.factions, factions) &&
      _setEquals(other.types, types) &&
      _setEquals(other.cycles, cycles) &&
      _setEquals(other.levels, levels);

  @override
  int get hashCode => Object.hash(
    searchText,
    deck,
    Object.hashAllUnordered(factions),
    Object.hashAllUnordered(types),
    Object.hashAllUnordered(cycles),
    Object.hashAllUnordered(levels),
  );

  static bool _setEquals<T>(Set<T> left, Set<T> right) =>
      left.length == right.length && left.containsAll(right);
}
