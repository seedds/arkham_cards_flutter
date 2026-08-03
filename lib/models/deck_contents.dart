import 'card.dart';
import 'card_database.dart';
import 'deck.dart';
import 'type_names.dart';

/// One card and how many copies the deck runs.
class DeckEntry {
  const DeckEntry({required this.card, required this.quantity});

  final Card card;
  final int quantity;
}

/// The cards of one type, as one titled group.
class DeckSection {
  const DeckSection({required this.typeCode, required this.entries});

  final String typeCode;
  final List<DeckEntry> entries;

  String get title => typeName(typeCode);

  /// Copies, not rows: three sections of "2x" is 6 cards.
  int get cardCount =>
      entries.fold(0, (total, entry) => total + entry.quantity);
}

/// A deck resolved against the card data and grouped for the screen.
///
/// **A code that resolves to nothing is counted, not dropped.** An imported
/// deck can name a card this bundle does not carry -- arkhamdb publishes new
/// products before this app's data is rebuilt -- and a deck quietly showing 28
/// of its 33 cards would read as correct. [unresolvedCodes] is what lets the
/// screen say otherwise.
class DeckContents {
  factory DeckContents(Deck deck, CardDatabase database) {
    final unresolved = <String>[];

    final investigator = database.card(deck.investigatorCode);
    if (investigator == null) unresolved.add(deck.investigatorCode);

    final sections = _group(deck.slots, database, unresolved);
    final sideSections = _group(deck.sideSlots, database, unresolved);

    return DeckContents._(
      investigator: investigator,
      sections: sections,
      sideSections: sideSections,
      unresolvedCodes: unresolved,
    );
  }

  const DeckContents._({
    required this.investigator,
    required this.sections,
    required this.sideSections,
    required this.unresolvedCodes,
  });

  /// Null only if the deck names an investigator this bundle does not have.
  final Card? investigator;
  final List<DeckSection> sections;
  final List<DeckSection> sideSections;

  /// Every code in the deck that no card matched, including the
  /// investigator's, in the order they were listed.
  final List<String> unresolvedCodes;

  /// Every card in the main deck, in the order the sections show them.
  ///
  /// One entry per card, not per copy: paging through two identical pages
  /// would be a bug, not a feature.
  List<Card> get cards => [
    for (final section in sections)
      for (final entry in section.entries) entry.card,
  ];

  /// The investigator and then every card, in the order the screen lists them.
  ///
  /// What the detail screen pages through, rather than [cards]: the
  /// investigator is a row like any other, so a swipe should reach it and
  /// leave it.
  List<Card> get pageSequence => [
    if (investigator case final Card card) card,
    ...cards,
  ];

  List<Card> get sideCards => [
    for (final section in sideSections)
      for (final entry in section.entries) entry.card,
  ];

  int get cardCount =>
      sections.fold(0, (total, section) => total + section.cardCount);

  int get sideCardCount =>
      sideSections.fold(0, (total, section) => total + section.cardCount);

  /// Slots into sections: by type in the game's own order, and by name within
  /// a type.
  ///
  /// Sorted by name rather than by code because a deck is read as a list of
  /// cards, not of positions -- and its cards come from many boxes, so code
  /// order interleaves them arbitrarily. Ties break on code, which is unique,
  /// so the order never depends on map iteration.
  static List<DeckSection> _group(
    Map<String, int> slots,
    CardDatabase database,
    List<String> unresolved,
  ) {
    final entriesByType = <String, List<DeckEntry>>{};

    // Sorted so that the unresolved codes come out in a fixed order too.
    for (final code in slots.keys.toList()..sort()) {
      final card = database.card(code);
      if (card == null) {
        unresolved.add(code);
        continue;
      }
      entriesByType
          .putIfAbsent(card.typeCode, () => [])
          .add(DeckEntry(card: card, quantity: slots[code]!));
    }

    final typeCodes = entriesByType.keys.toList()
      ..sort((left, right) {
        final order = _rank(left).compareTo(_rank(right));
        // Two unrecognised types share a rank, so they need a tiebreak of
        // their own or their order depends on map iteration.
        return order != 0 ? order : left.compareTo(right);
      });

    return [
      for (final typeCode in typeCodes)
        DeckSection(
          typeCode: typeCode,
          entries: entriesByType[typeCode]!
            ..sort((left, right) {
              final order = left.card.name.compareTo(right.card.name);
              return order != 0
                  ? order
                  : left.card.code.compareTo(right.card.code);
            }),
        ),
    ];
  }

  /// A type's place in the game's canonical ordering, with anything
  /// unrecognised sorted to the end rather than to the front.
  static int _rank(String typeCode) {
    final index = TypeOrder.all.indexOf(typeCode);
    return index == -1 ? TypeOrder.all.length : index;
  }
}
