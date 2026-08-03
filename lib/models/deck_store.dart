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
    required this.starters,
    required this.storeFile,
    this.client = const ArkhamDBClient(),
  }) : _imported = _read(storeFile);

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

  /// The 10 Investigator Starter Decks. Fixed, and in release order.
  final List<Deck> starters;

  /// Where the imported decks are kept. Null if Application Support could not
  /// be reached, in which case they last only as long as the process.
  final File? storeFile;

  /// Injectable so the tests can import a deck without a network.
  final ArkhamDBClient client;
  final List<Deck> _imported;

  /// Imported decks, most recently added last.
  List<Deck> get imported => List.unmodifiable(_imported);

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

  void remove(Deck deck) {
    if (!deck.isImported) return;
    _imported.removeWhere((held) => held.id == deck.id);
    _save();
    notifyListeners();
  }

  static List<Deck> _read(File? file) {
    if (file == null || !file.existsSync()) return [];
    try {
      final records = jsonDecode(file.readAsStringSync()) as List<Object?>;
      return [
        for (final record in records)
          Deck.fromJson(record! as Map<String, Object?>),
      ];
    } catch (_) {
      // A store written by an older version, or half-written, reads as no
      // decks rather than as a launch failure. The only thing lost is a list
      // the user can fetch again.
      return [];
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
        jsonEncode([for (final deck in _imported) deck.toJson()]),
        flush: true,
      );
      temporary.renameSync(file.path);
    } catch (_) {
      // Nothing useful to do: the decks are still in memory and still on
      // screen, and the user can re-import them next launch.
    }
  }
}
