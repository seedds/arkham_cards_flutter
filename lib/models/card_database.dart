import 'dart:convert';

import 'card.dart';
import 'card_query.dart';

/// The canonical class ordering used by the game's own products.
abstract final class FactionOrder {
  static const all = [
    'guardian',
    'seeker',
    'rogue',
    'mystic',
    'survivor',
    'neutral',
    'mythos',
  ];
}

abstract final class TypeOrder {
  static const all = [
    'investigator',
    'asset',
    'event',
    'skill',
    'enemy',
    'treachery',
    'location',
    'enemy_location',
    'act',
    'agenda',
    'scenario',
    'story',
    'key',
  ];
}

class Cycle {
  const Cycle({required this.code, required this.name});

  final String code;
  final String name;

  @override
  bool operator ==(Object other) => other is Cycle && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Every card, indexed for the three questions the app asks of them: find one
/// by code, find the ones matching a query, and find a card's other versions.
///
/// Built once at launch and immutable after, so every index can be eager.
class CardDatabase {
  CardDatabase(List<Card> cards) : all = List.unmodifiable(cards) {
    for (final card in cards) {
      // First wins, matching the Swift original. No two records share a code
      // in the bundled data, so this only decides a case that cannot arise.
      _byCode.putIfAbsent(card.code, () => card);
      _searchText.putIfAbsent(card.code, () => fold(card.name));
    }

    _groupPrintings(cards);

    factions = _orderedValues(
      FactionOrder.all,
      cards.expand((card) => card.factions),
    );
    types = _orderedValues(TypeOrder.all, cards.map((card) => card.typeCode));
    levels = cards.map((card) => card.level).toSet().toList()..sort();

    // First-appearance order, which is release order because `all` is sorted
    // by sort_key. Not alphabetical: the cycles are read as a timeline.
    final seen = <String>{};
    for (final card in cards) {
      if (card.cycleCode.isEmpty || !seen.add(card.cycleCode)) continue;
      cycles.add(Cycle(code: card.cycleCode, name: card.cycleName));
      _cycleNamesByCode[card.cycleCode] = card.cycleName;
    }
  }

  /// Decodes the bundled `cards.json`, which is one array of every card.
  factory CardDatabase.fromJson(String source) {
    final records = jsonDecode(source) as List<Object?>;
    return CardDatabase([
      for (final record in records) Card.fromJson(record! as Map<String, Object?>),
    ]);
  }

  /// Every card, in the order the build script wrote them: cycle, pack,
  /// position. This is the order the list shows, so it is not re-sorted.
  final List<Card> all;

  final Map<String, Card> _byCode = {};
  final Map<String, String> _searchText = {};
  final Map<String, List<Card>> _printingsByRoot = {};
  final Map<String, String> _rootByCode = {};
  final Map<String, String> _cycleNamesByCode = {};

  late final List<String> factions;
  late final List<String> types;
  final List<Cycle> cycles = [];
  late final List<int> levels;

  Card? card(String code) => _byCode[code];

  String cycleName(String code) => _cycleNamesByCode[code] ?? code;

  Card? back(Card card) {
    final link = card.backLink;
    return link == null ? null : _byCode[link];
  }

  /// Every version of a card, in release order, including the card itself.
  ///
  /// Two different relations end up in one group, because both answer the same
  /// question -- what else is this card:
  ///
  /// - A card reprinted in a later box (Revised Core, Core 2026, an
  ///   investigator starter deck) is a separate record pointing back at the
  ///   original, and its art differs.
  /// - A card printed several times at one number in one box is a set of
  ///   siblings: `Hunter's Hunger` is two cards in Fortune and Folly with
  ///   different suit pips, `Heretic` is six in The Wages of Sin.
  ///
  /// A card that is neither returns just itself, which lets a caller treat
  /// every card the same way.
  List<Card> printings(Card card) {
    final root = _rootByCode[card.code] ?? card.code;
    return _printingsByRoot[root] ?? [card];
  }

  /// Cards matching a query, in bundled order.
  List<Card> cards(CardQuery query) {
    final match = _matcher(query);
    return [
      for (final card in all)
        if (match(card)) card,
    ];
  }

  /// How many cards a query matches.
  ///
  /// Counted without building the list, because the filter sheet recounts on
  /// every keystroke and most queries match thousands of cards.
  int count(CardQuery query) {
    final match = _matcher(query);
    var total = 0;
    for (final card in all) {
      if (match(card)) total++;
    }
    return total;
  }

  bool Function(Card) _matcher(CardQuery query) {
    // Folded once for the query rather than once per card.
    final needles = fold(query.searchText)
        .split(' ')
        .where((needle) => needle.isNotEmpty)
        .toList();

    return (card) => query.matches(card) && _matchesText(card, needles);
  }

  /// Every needle must appear somewhere in the card's name, so extra words
  /// narrow the result rather than widening it.
  bool _matchesText(Card card, List<String> needles) {
    if (needles.isEmpty) return true;
    final haystack = _searchText[card.code];
    if (haystack == null) return false;
    return needles.every(haystack.contains);
  }

  /// Build the version groups once, up front.
  ///
  /// Two quirks in the upstream pointers are settled here: five cards carry
  /// both a `duplicate_of` and an `alternate_of` (both naming the same
  /// original), and one points at a card that is itself a reprint, so
  /// following the pointers has to repeat until it reaches a card that has
  /// none.
  void _groupPrintings(List<Card> cards) {
    String rootOf(Card card) {
      var current = card;
      // Bounded by the longest chain in the data, which is two links. The
      // guard is against a cycle, not against depth.
      final visited = <String>{current.code};
      while (true) {
        // All three mean "this is another version of that", so one walk
        // handles reprints and same-box variants alike. No card carries a
        // variant pointer and a reprint pointer -- the build script reports it
        // rather than linking if that ever changes.
        final pointer =
            current.duplicateOf ?? current.alternateOf ?? current.variantOf;
        if (pointer == null) break;
        final next = _byCode[pointer];
        if (next == null || !visited.add(next.code)) break;
        current = next;
      }
      return current.code;
    }

    for (final card in cards) {
      final root = rootOf(card);
      _rootByCode[card.code] = root;
      _printingsByRoot.putIfAbsent(root, () => []).add(card);
    }

    // Release order, so the original comes first and later boxes follow.
    for (final group in _printingsByRoot.values) {
      if (group.length < 2) continue;
      group.sort((left, right) {
        final order = _compareSortKeys(left.sortKey, right.sortKey);
        return order != 0 ? order : left.code.compareTo(right.code);
      });
    }
  }

  static int _compareSortKeys(List<int> left, List<int> right) {
    for (var index = 0; index < left.length && index < right.length; index++) {
      final order = left[index].compareTo(right[index]);
      if (order != 0) return order;
    }
    return left.length.compareTo(right.length);
  }

  /// Values from [order] that occur in [present], keeping the canonical
  /// ordering and appending anything unexpected at the end.
  static List<String> _orderedValues(
    List<String> order,
    Iterable<String> present,
  ) {
    final found = present.toSet();
    return [
      ...order.where(found.contains),
      ...found.where((value) => !order.contains(value)).toList()..sort(),
    ];
  }

  /// Lowercased and stripped of accents, so "Luís" is found by typing "luis".
  ///
  /// This is Foundation's `.diacriticInsensitive, .caseInsensitive` folding as
  /// the Swift app used it, which decomposes and drops combining marks but
  /// leaves a ligature alone: `Chœur Gothique` is not found by typing "choeur"
  /// there and is not here either.
  static String fold(String text) {
    final decomposed = _decompose(text);
    final buffer = StringBuffer();
    for (final rune in decomposed.runes) {
      if (_isCombiningMark(rune)) continue;
      buffer.writeCharCode(rune);
    }
    return buffer.toString().toLowerCase();
  }

  static bool _isCombiningMark(int rune) =>
      (rune >= 0x0300 && rune <= 0x036F) || // combining diacritical marks
      (rune >= 0x1AB0 && rune <= 0x1AFF) ||
      (rune >= 0x1DC0 && rune <= 0x1DFF) ||
      (rune >= 0x20D0 && rune <= 0x20FF) ||
      (rune >= 0xFE20 && rune <= 0xFE2F);

  /// Canonical decomposition of the Latin-1 and Latin Extended-A letters that
  /// occur in the card names, which is all of them: 18 distinct non-ASCII
  /// characters across 5,928 names.
  ///
  /// Dart has no NFD in its core library and this app has no other reason to
  /// depend on one. A character not in the table passes through unchanged,
  /// which is the right answer for the bullet, ellipsis, middle dot and `œ`
  /// that make up the rest of the set.
  static String _decompose(String text) {
    if (!text.runes.any((rune) => rune > 0x7F)) return text;
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final base = _latinBase[rune];
      if (base != null) {
        buffer.write(base);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static const Map<int, String> _latinBase = {
    0x00C0: 'A', 0x00C1: 'A', 0x00C2: 'A', 0x00C3: 'A', 0x00C4: 'A',
    0x00C5: 'A', 0x00C7: 'C', 0x00C8: 'E', 0x00C9: 'E', 0x00CA: 'E',
    0x00CB: 'E', 0x00CC: 'I', 0x00CD: 'I', 0x00CE: 'I', 0x00CF: 'I',
    0x00D1: 'N', 0x00D2: 'O', 0x00D3: 'O', 0x00D4: 'O', 0x00D5: 'O',
    0x00D6: 'O', 0x00D9: 'U', 0x00DA: 'U', 0x00DB: 'U', 0x00DC: 'U',
    0x00DD: 'Y',
    0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a', 0x00E4: 'a',
    0x00E5: 'a', 0x00E7: 'c', 0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e',
    0x00EB: 'e', 0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
    0x00F1: 'n', 0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F5: 'o',
    0x00F6: 'o', 0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
    0x00FD: 'y', 0x00FF: 'y',
    0x0100: 'A', 0x0101: 'a', 0x0102: 'A', 0x0103: 'a', 0x0104: 'A',
    0x0105: 'a', 0x0106: 'C', 0x0107: 'c', 0x010C: 'C', 0x010D: 'c',
    0x010E: 'D', 0x010F: 'd', 0x0112: 'E', 0x0113: 'e', 0x0118: 'E',
    0x0119: 'e', 0x011A: 'E', 0x011B: 'e', 0x011E: 'G', 0x011F: 'g',
    0x0130: 'I', 0x012A: 'I', 0x012B: 'i', 0x0141: 'L', 0x0142: 'l',
    0x0143: 'N', 0x0144: 'n', 0x0147: 'N', 0x0148: 'n', 0x014C: 'O',
    0x014D: 'o', 0x0150: 'O', 0x0151: 'o', 0x0154: 'R', 0x0155: 'r',
    0x0158: 'R', 0x0159: 'r', 0x015A: 'S', 0x015B: 's', 0x015E: 'S',
    0x015F: 's', 0x0160: 'S', 0x0161: 's', 0x0162: 'T', 0x0163: 't',
    0x0164: 'T', 0x0165: 't', 0x016A: 'U', 0x016B: 'u', 0x016E: 'U',
    0x016F: 'u', 0x0170: 'U', 0x0171: 'u', 0x0179: 'Z', 0x017A: 'z',
    0x017B: 'Z', 0x017C: 'z', 0x017D: 'Z', 0x017E: 'z',
  };
}
