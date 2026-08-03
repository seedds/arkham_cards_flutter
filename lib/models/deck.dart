import 'dart:convert';

/// Where a deck came from, and so whether the user may remove it.
sealed class DeckSource {
  const DeckSource();

  factory DeckSource.fromJson(Map<String, Object?> json) {
    final starter = json['starter'] as Map<String, Object?>?;
    if (starter != null) {
      return StarterSource(starter['packCode']! as String);
    }
    final imported = json['imported'] as Map<String, Object?>?;
    if (imported != null) {
      return ImportedSource(imported['decklistID']! as int);
    }
    throw FormatException('Unrecognised deck source: $json');
  }

  Map<String, Object?> toJson();
}

/// Derived from a pack file by the build script.
class StarterSource extends DeckSource {
  const StarterSource(this.packCode);

  final String packCode;

  @override
  Map<String, Object?> toJson() => {
    'starter': {'packCode': packCode},
  };

  @override
  bool operator ==(Object other) =>
      other is StarterSource && other.packCode == packCode;

  @override
  int get hashCode => Object.hash('starter', packCode);
}

/// Fetched from `arkhamdb.com/api/public/decklist/{id}`.
class ImportedSource extends DeckSource {
  const ImportedSource(this.decklistID);

  final int decklistID;

  @override
  Map<String, Object?> toJson() => {
    'imported': {'decklistID': decklistID},
  };

  @override
  bool operator ==(Object other) =>
      other is ImportedSource && other.decklistID == decklistID;

  @override
  int get hashCode => Object.hash('imported', decklistID);
}

/// A deck: an investigator, and how many copies of each card.
///
/// [slots] maps a card code to a quantity. Codes, not cards: an imported deck
/// is stored on disk and read back later, possibly against a bundle that no
/// longer has one of its cards, and a deck that could not decode without a
/// card database could not be persisted at all. Resolving codes to cards is
/// `DeckContents`'s job.
class Deck {
  const Deck({
    required this.source,
    required this.name,
    required this.investigatorCode,
    required this.slots,
    required this.sideSlots,
  });

  factory Deck.fromJson(Map<String, Object?> json) => Deck(
    source: DeckSource.fromJson(json['source']! as Map<String, Object?>),
    name: json['name']! as String,
    investigatorCode: json['investigator_code']! as String,
    slots: _slots(json['slots']),
    sideSlots: _slots(json['sideSlots']),
  );

  /// The ten Investigator Starter Decks, in the order the build script wrote
  /// them, which is release order.
  ///
  /// `decks.json` is the build script's shape rather than this one's: it has a
  /// pack code where a deck has a source, and no side deck at all.
  static List<Deck> parseBundledStarters(String source) {
    final records = jsonDecode(source) as List<Object?>;
    return [
      for (final record in records)
        if (record case final Map<String, Object?> json)
          Deck(
            source: StarterSource(json['pack_code']! as String),
            name: json['name']! as String,
            investigatorCode: json['investigator_code']! as String,
            slots: _slots(json['slots']),
            // A starter deck is a fixed product with nothing on the side.
            sideSlots: const {},
          ),
    ];
  }

  static Map<String, int> _slots(Object? json) {
    // An empty side deck arrives as `[]` rather than `{}`, because PHP renders
    // an empty associative array as a JSON array. That is most decks on
    // arkhamdb, not an edge case.
    if (json is! Map) return const {};
    return {
      for (final entry in json.entries)
        entry.key as String: entry.value as int,
    };
  }

  final DeckSource source;
  final String name;
  final String investigatorCode;
  final Map<String, int> slots;

  /// Cards named as a side deck by arkhamdb. Always empty for a starter deck.
  final Map<String, int> sideSlots;

  String get id => switch (source) {
    StarterSource(:final packCode) => 'starter:$packCode',
    ImportedSource(:final decklistID) => 'arkhamdb:$decklistID',
  };

  bool get isImported => source is ImportedSource;

  /// Copies in the main deck. The side deck is counted separately because it
  /// is not part of the 30-odd cards a deck is built to.
  int get cardCount => slots.values.fold(0, (total, count) => total + count);

  Map<String, Object?> toJson() => {
    'source': source.toJson(),
    'name': name,
    'investigator_code': investigatorCode,
    'slots': slots,
    'sideSlots': sideSlots,
  };

  @override
  bool operator ==(Object other) => other is Deck && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Deck($id $name)';
}
