/// Dumps what the Dart models compute, for diffing against the Swift ones.
///
/// The ported tests prove Dart agrees with the assertions someone wrote down.
/// They cannot prove it agrees with the Swift code, which is the thing being
/// replaced -- an ordering rule read slightly wrong would satisfy both. This
/// dumps the three answers most likely to drift, and `tools/crosscheck.sh`
/// diffs them against the same dump from the Swift build.
///
///     dart run tools/dump_dart.dart > /tmp/dart.txt
library;

import 'dart:convert';
import 'dart:io';

import 'package:arkham_cards/models/card_database.dart';
import 'package:arkham_cards/models/card_query.dart';
import 'package:arkham_cards/models/deck.dart';
import 'package:arkham_cards/models/deck_contents.dart';

/// Search terms chosen to exercise folding, multi-word narrowing, and the
/// names that collide.
const searches = [
  '',
  'a',
  'the',
  'roland',
  'roland banks',
  'shotgun',
  'SHOTGUN',
  'luis',
  'andre',
  'chœur',
  'choeur',
  'hunter',
  "hunter's hunger",
  'heretic',
  'deduction',
  'physical training',
  'e',
  'of the',
];

void main() {
  final database = CardDatabase.fromJson(
    File('assets/cards.json').readAsStringSync(),
  );
  final starters = Deck.parseBundledStarters(
    File('assets/decks.json').readAsStringSync(),
  );
  final out = stdout;

  out.writeln('## order');
  for (final card in database.all) {
    out.writeln(card.code);
  }

  out.writeln('## printings');
  // Only the group's own root emits it, so each group is dumped once.
  for (final card in database.all) {
    final group = database.printings(card);
    if (group.first.code != card.code) continue;
    out.writeln('${card.code}: ${group.map((c) => c.code).join(",")}');
  }

  out.writeln('## search');
  for (final term in searches) {
    final results = database.cards(CardQuery(searchText: term));
    out.writeln(
      '${jsonEncode(term)}: ${results.length} '
      '${results.take(20).map((c) => c.code).join(",")}',
    );
  }

  out.writeln('## filters');
  for (final faction in database.factions) {
    out.writeln(
      'faction $faction: ${database.count(CardQuery(factions: {faction}))}',
    );
  }
  for (final type in database.types) {
    out.writeln('type $type: ${database.count(CardQuery(types: {type}))}');
  }
  for (final level in database.levels) {
    out.writeln('level $level: ${database.count(CardQuery(levels: {level}))}');
  }
  for (final cycle in database.cycles) {
    out.writeln(
      'cycle ${cycle.code}: ${database.count(CardQuery(cycles: {cycle.code}))}',
    );
  }
  for (final deck in DeckKind.values) {
    out.writeln('deck ${deck.name}: ${database.count(CardQuery(deck: deck))}');
  }
  // Combinations, since the categories AND together and classes OR within.
  out.writeln(
    'guardian+seeker: '
    '${database.count(const CardQuery(factions: {'guardian', 'seeker'}))}',
  );
  out.writeln(
    'guardian asset level 0: '
    '${database.count(const CardQuery(factions: {'guardian'}, types: {'asset'}, levels: {0}))}',
  );

  out.writeln('## decks');
  for (final deck in starters) {
    final contents = DeckContents(deck, database);
    out.writeln('${deck.id} ${deck.name} ${contents.cardCount}');
    for (final section in contents.sections) {
      out.writeln('  ${section.typeCode} ${section.cardCount}');
      for (final entry in section.entries) {
        out.writeln('    ${entry.quantity} ${entry.card.code} ${entry.card.name}');
      }
    }
    out.writeln('  page ${contents.pageSequence.map((c) => c.code).join(",")}');
  }
}
