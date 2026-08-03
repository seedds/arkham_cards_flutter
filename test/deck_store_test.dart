import 'dart:convert';
import 'dart:io';

import 'package:arkham_cards/models/deck.dart';
import 'package:arkham_cards/models/deck_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Persistence, which is the part of the decks tab that has to survive a
/// relaunch. Each test writes to a temporary file of its own rather than to
/// the real store.
void main() {
  late Directory temporary;
  late File storeFile;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('arkham-decks');
    storeFile = File('${temporary.path}/imported-decks.json');
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  Deck deck(int id, {String name = 'A deck'}) => Deck(
    source: ImportedSource(id),
    name: name,
    investigatorCode: '01001',
    slots: const {'01006': 1},
    sideSlots: const {},
  );

  DeckStore store({List<Deck> starters = const []}) =>
      DeckStore(starters: starters, storeFile: storeFile);

  test('empty store has no imported decks', () {
    // A missing file is not a failure.
    expect(store().imported, isEmpty);
  });

  test('imported decks survive a relaunch', () {
    // The point of persisting: a deck imported once opens again without a
    // connection, and after the app has been closed.
    store().add(deck(40838, name: 'The Jenny Barnes Job'));

    final reopened = store();
    expect(reopened.imported.length, 1);
    expect(reopened.imported.first.name, 'The Jenny Barnes Job');
    expect(reopened.imported.first.source, const ImportedSource(40838));
    expect(reopened.imported.first.slots, {'01006': 1});
  });

  test('reimporting replaces rather than duplicates', () {
    // Decks on arkhamdb are edited after publication, and the newer fetch is
    // the better one.
    final held = store()
      ..add(deck(40838, name: 'Original name'))
      ..add(deck(40838, name: 'Renamed by its author'));

    expect(held.imported.length, 1);
    expect(held.imported.first.name, 'Renamed by its author');
  });

  test('reimporting keeps the deck in its place', () {
    final held = store()
      ..add(deck(1, name: 'First'))
      ..add(deck(2, name: 'Second'))
      ..add(deck(1, name: 'First, revised'));

    expect(
      held.imported.map((deck) => deck.name).toList(),
      ['First, revised', 'Second'],
    );
  });

  test('removing an imported deck persists', () {
    final held = store()
      ..add(deck(1))
      ..add(deck(2));
    held.remove(held.imported[0]);

    expect(held.imported.length, 1);
    expect(_reload(storeFile).length, 1);
  });

  test('starter decks cannot be removed', () {
    // A starter deck is part of the app. Asking to remove one does nothing
    // rather than emptying the tab.
    const starter = Deck(
      source: StarterSource('nat'),
      name: 'Nathaniel Cho',
      investigatorCode: '60101',
      slots: {'60105': 2},
      sideSlots: {},
    );
    final held = store(starters: const [starter])..remove(starter);
    expect(held.starters.length, 1);
  });

  test('unreadable store loads as empty', () {
    // A store file that will not decode -- written by an older version, or
    // half-written -- costs the user a list they can fetch again, not the
    // launch.
    storeFile.writeAsStringSync('this is not json');
    expect(_reload(storeFile), isEmpty);
  });

  test('deck round trips through JSON', () {
    const original = Deck(
      source: ImportedSource(40838),
      name: 'Rexploding Performance',
      investigatorCode: '02002',
      slots: {'09041': 2, '01030': 2},
      sideSlots: {'01043': 2},
    );
    final decoded = Deck.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
    );

    expect(decoded, original);
    expect(decoded.name, original.name);
    expect(decoded.investigatorCode, original.investigatorCode);
    expect(decoded.slots, original.slots);
    expect(decoded.sideSlots, {'01043': 2});
  });

  test('a starter source round trips too', () {
    const original = Deck(
      source: StarterSource('nat'),
      name: 'Nathaniel Cho',
      investigatorCode: '60101',
      slots: {'60105': 2},
      sideSlots: {},
    );
    final decoded = Deck.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
    );
    expect(decoded.source, const StarterSource('nat'));
    expect(decoded.id, 'starter:nat');
  });

  test('deck ids name their source', () {
    expect(deck(40838).id, 'arkhamdb:40838');
    expect(deck(40838).isImported, isTrue);
    expect(deck(40838).cardCount, 1);
  });
}

/// The decks a fresh store would read from this file.
List<Deck> _reload(File file) =>
    DeckStore(starters: const [], storeFile: file).imported;
