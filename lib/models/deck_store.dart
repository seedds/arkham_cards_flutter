import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'arkhamdb_client.dart';
import 'deck.dart';

/// The starter decks, the imported decks, and the file the latter live in.
///
/// Imported decks are written to disk as they arrive, so a deck fetched once
/// opens offline afterwards. That is the point of storing the cards rather
/// than the id -- the app is otherwise entirely offline, and a decks tab that
/// needed a connection to show a deck already imported would be the only part
/// of it that did not work on a train.
class DeckStore extends ChangeNotifier {
  /// Reads whatever the store file already holds.
  ///
  /// Reading here rather than in a separate step is what makes a second store
  /// over the same file see the first one's decks, which is the whole of what
  /// persistence means to this app.
  DeckStore({
    required List<Deck> starters,
    required this.storeFile,
    this.client = const ArkhamDBClient(),
  }) : _allStarters = starters,
       _held = _read(storeFile);

  /// Reads the store file, and the starters from the bundled `decks.json`.
  static Future<DeckStore> load({
    required String decksJson,
    File? storeFile,
    ArkhamDBClient client = const ArkhamDBClient(),
  }) async {
    // A missing or unreadable decks.json leaves the tab with no starters
    // rather than stopping the app: the card browser is the app's reason to
    // exist and still works without them.
    List<Deck> starters;
    try {
      starters = Deck.parseBundledStarters(decksJson);
    } catch (_) {
      starters = const [];
    }

    return DeckStore(
      starters: starters,
      storeFile: storeFile ?? await defaultStoreFile(),
      client: client,
    );
  }

  /// One file for the whole list, not one per deck.
  ///
  /// The decks are a few kilobytes together, so there is nothing to gain from
  /// separate files and a directory to keep reconciled.
  static Future<File?> defaultStoreFile() async {
    try {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      return File('${directory.path}/imported-decks.json');
    } catch (_) {
      return null;
    }
  }

  /// The 10 Investigator Starter Decks as bundled, including any the user has
  /// since deleted. [starters] is the list to show.
  final List<Deck> _allStarters;

  /// Where the imported decks are kept. Null if Application Support could not
  /// be reached, in which case they last only as long as the process.
  final File? storeFile;

  /// Injectable so the tests can import a deck without a network.
  final ArkhamDBClient client;
  final _Held _held;

  List<Deck> get _imported => _held.imported;

  /// Imported decks, most recently added last.
  List<Deck> get imported => List.unmodifiable(_imported);

  /// The starter decks still on show, in bundled order.
  ///
  /// Derived on each read rather than stored, so restoring one puts it back
  /// where it was published rather than at the end.
  List<Deck> get starters => [
    for (final deck in _allStarters)
      if (!_held.hiddenStarters.contains(deck.id)) deck,
  ];

  /// How many starters the user has deleted. Drives the Settings row that
  /// brings them back, which is the only route to undoing a deletion.
  int get hiddenStarterCount => _held.hiddenStarters.length;

  /// Fetch a published decklist and keep it.
  Future<Deck> importDecklist(int id) async {
    final deck = await client.decklist(id);
    add(deck);
    return deck;
  }

  /// Keep a deck, replacing one already held under the same id.
  ///
  /// Re-importing replaces rather than adding a second copy, since decks on
  /// arkhamdb are edited after publication and the newer fetch is the better
  /// one. The replacement keeps the original's place in the list.
  void add(Deck deck) {
    final existing = _imported.indexWhere((held) => held.id == deck.id);
    if (existing >= 0) {
      _imported[existing] = deck;
    } else {
      _imported.add(deck);
    }
    _save();
    notifyListeners();
  }

  /// Drop an imported deck, or hide a starter.
  ///
  /// A starter is bundled and cannot be deleted in any real sense, so it is
  /// recorded as hidden instead. That is what makes it restorable, and the
  /// Settings row that restores them is the only way back -- so hiding one is
  /// undoable where dropping an import is not.
  void remove(Deck deck) {
    if (deck.isImported) {
      _imported.removeWhere((held) => held.id == deck.id);
    } else {
      _held.hiddenStarters.add(deck.id);
    }
    _save();
    notifyListeners();
  }

  /// Put every hidden starter back.
  void restoreStarters() {
    if (_held.hiddenStarters.isEmpty) return;
    _held.hiddenStarters.clear();
    _save();
    notifyListeners();
  }

  static _Held _read(File? file) {
    if (file == null || !file.existsSync()) return _Held.empty();
    try {
      final json = jsonDecode(file.readAsStringSync());
      // A bare array is the format written before hidden starters needed
      // somewhere to live. Reading it as an object would drop every deck the
      // user had imported, silently, on upgrade.
      final records = json is List ? json : (json as Map)['imported'] as List;
      final hidden = json is Map
          ? (json['hiddenStarters'] as List?) ?? const []
          : const [];
      return _Held(
        imported: [
          for (final record in records)
            Deck.fromJson(record! as Map<String, Object?>),
        ],
        hiddenStarters: {for (final id in hidden) id! as String},
      );
    } catch (_) {
      // A store written by an older version, or half-written, reads as no
      // decks rather than as a launch failure. The only thing lost is a list
      // the user can fetch again.
      return _Held.empty();
    }
  }

  void _save() {
    final file = storeFile;
    if (file == null) return;
    try {
      // Written beside the real file and moved into place, so an interrupted
      // write cannot leave a half-file that reads as no decks at all.
      final temporary = File('${file.path}.tmp');
      temporary.writeAsStringSync(
        jsonEncode({
          'imported': [for (final deck in _imported) deck.toJson()],
          'hiddenStarters': _held.hiddenStarters.toList()..sort(),
        }),
        flush: true,
      );
      temporary.renameSync(file.path);
    } catch (_) {
      // Nothing useful to do: the decks are still in memory and still on
      // screen, and the user can re-import them next launch.
    }
  }
}

/// What the store file holds: the imported decks, and which starters the user
/// has deleted.
///
/// Both in one file because they are written together -- hiding a starter and
/// dropping an import are the same save, and two files would need reconciling
/// after a half-completed one.
class _Held {
  _Held({required this.imported, required this.hiddenStarters});

  _Held.empty() : imported = [], hiddenStarters = {};

  final List<Deck> imported;

  /// `Deck.id`s, so `starter:nat`.
  final Set<String> hiddenStarters;
}
