import 'dart:convert';
import 'dart:io';

import 'deck.dart';

/// What went wrong fetching a decklist.
///
/// This is the app's only network call, so these are its only failure modes,
/// and they are spelled out rather than collapsed into a generic error.
sealed class ArkhamDBError implements Exception {
  const ArkhamDBError();

  String get message;
}

/// No decklist with that id, which arkhamdb reports as an empty body.
class DecklistNotFound extends ArkhamDBError {
  const DecklistNotFound();

  @override
  String get message => 'No published decklist has that number.';

  @override
  bool operator ==(Object other) => other is DecklistNotFound;

  @override
  int get hashCode => 'notFound'.hashCode;
}

/// The request never completed: no network, DNS, timeout.
class ArkhamDBUnreachable extends ArkhamDBError {
  const ArkhamDBUnreachable(this.detail);

  final String detail;

  @override
  String get message => 'Could not reach arkhamdb. Check your connection.';

  @override
  bool operator ==(Object other) => other is ArkhamDBUnreachable;

  @override
  int get hashCode => 'unreachable'.hashCode;
}

class ArkhamDBServerError extends ArkhamDBError {
  const ArkhamDBServerError(this.statusCode);

  final int statusCode;

  @override
  String get message => 'arkhamdb returned an error ($statusCode).';

  @override
  bool operator ==(Object other) =>
      other is ArkhamDBServerError && other.statusCode == statusCode;

  @override
  int get hashCode => Object.hash('server', statusCode);
}

/// A 200 whose body is not the decklist shape.
class ArkhamDBMalformed extends ArkhamDBError {
  const ArkhamDBMalformed();

  @override
  String get message => 'arkhamdb sent something this app could not read.';

  @override
  bool operator ==(Object other) => other is ArkhamDBMalformed;

  @override
  int get hashCode => 'malformed'.hashCode;
}

/// Fetches a published decklist from arkhamdb.
///
/// **`decklist`, not `deck`.** arkhamdb has both, and only one is public: a
/// `/api/public/deck/{id}` request for someone else's deck answers 302 to the
/// login page, because that endpoint serves the caller's own decks over
/// OAuth2. `/api/public/decklist/{id}` is a deck its author published, and
/// needs no credentials. The id in an `arkhamdb.com/deck/view/...` URL will not
/// resolve here; the one in a `/decklist/view/...` URL will.
class ArkhamDBClient {
  const ArkhamDBClient({this.fetch = _fetch});

  /// Injectable so the tests can exercise the failure modes without a network.
  final Future<({int statusCode, String body})> Function(Uri url) fetch;

  static const host = 'arkhamdb.com';

  Future<Deck> decklist(int id) async {
    if (id <= 0) throw const DecklistNotFound();

    final url = Uri.https(host, '/api/public/decklist/$id');

    final ({int statusCode, String body}) response;
    try {
      response = await fetch(url);
    } on ArkhamDBError {
      rethrow;
    } catch (error) {
      throw ArkhamDBUnreachable(error.toString());
    }

    if (response.statusCode != 200) {
      throw ArkhamDBServerError(response.statusCode);
    }

    // An unknown id answers 200 with an empty body, not 404, so this is the
    // ordinary "no such deck" path rather than an edge case.
    if (response.body.isEmpty) throw const DecklistNotFound();

    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return Deck(
        source: ImportedSource(id),
        name: json['name']! as String,
        investigatorCode: json['investigator_code']! as String,
        slots: _slots(json['slots'], required: true),
        // An empty side deck is serialised as `[]`, a non-empty one as an
        // object. PHP renders an empty associative array as a JSON array, so
        // this is not an occasional quirk -- it is every deck without a side
        // deck, which is most of them.
        sideSlots: _slots(json['sideSlots'], required: false),
      );
    } catch (_) {
      throw const ArkhamDBMalformed();
    }
  }

  static Map<String, int> _slots(Object? json, {required bool required}) {
    if (json is Map) {
      return {
        for (final entry in json.entries)
          entry.key as String: (entry.value as num).toInt(),
      };
    }
    // A main deck that is not an object is a decklist this app cannot read; a
    // side deck that is not one is the ordinary empty case.
    if (required) throw const ArkhamDBMalformed();
    return const {};
  }

  static Future<({int statusCode, String body})> _fetch(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return (statusCode: response.statusCode, body: body);
    } finally {
      client.close();
    }
  }
}
