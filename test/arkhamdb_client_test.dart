import 'package:arkham_cards/models/arkhamdb_client.dart';
import 'package:arkham_cards/models/deck.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one network call, exercised without a network.
void main() {
  /// A client answering every request with one canned response.
  ArkhamDBClient serving(String body, {int statusCode = 200}) =>
      ArkhamDBClient(fetch: (_) async => (statusCode: statusCode, body: body));

  Future<Deck> decode(String body, {int id = 1}) =>
      serving(body).decklist(id);

  group('decoding', () {
    test('decodes a decklist', () async {
      final deck = await decode('''
{"id":1,"name":"Roland Banks Starter Deck","investigator_code":"01001",
 "investigator_name":"Roland Banks",
 "slots":{"01006":1,"01086":2},"sideSlots":[]}
''');
      expect(deck.name, 'Roland Banks Starter Deck');
      expect(deck.investigatorCode, '01001');
      expect(deck.slots, {'01006': 1, '01086': 2});
    });

    test('empty side deck arrives as an array', () async {
      // PHP renders an empty associative array as a JSON array, so this is not
      // a rare edge case -- it is every deck without a side deck, which is most
      // of them. Decoding sideSlots as a map outright would fail on roughly
      // half the decks on the site.
      final deck = await decode(
        '{"name":"No side deck","investigator_code":"01001",'
        '"slots":{"01006":1},"sideSlots":[]}',
      );
      expect(deck.sideSlots, isEmpty);
    });

    test('populated side deck arrives as an object', () async {
      final deck = await decode(
        '{"name":"With a side deck","investigator_code":"02002",'
        '"slots":{"01030":2},"sideSlots":{"01043":2,"03150":2}}',
      );
      expect(deck.sideSlots, {'01043': 2, '03150': 2});
    });

    test('ignores the fields the app does not use', () async {
      // The response carries xp, taboo ids, customisation metadata and a chain
      // of previous versions. None of it is used, and none of it may stop the
      // deck being read.
      final deck = await decode('''
{"id":40838,"name":"Rexploding Performance","investigator_code":"02002",
 "slots":{"09041":2},"sideSlots":{"01043":2},
 "xp":6,"xp_spent":6,"taboo_id":7,"exile_string":null,
 "meta":"{\\"cus_09041\\":\\"3|1,7|4,5|2\\"}",
 "previous_deck":40839,"next_deck":null,"ignoreDeckLimitSlots":null}
''');
      expect(deck.name, 'Rexploding Performance');
      expect(deck.slots, {'09041': 2});
    });

    test('becomes an imported deck', () async {
      // A decklist becomes a deck that knows where it came from and can be
      // deleted.
      final deck = await decode(
        '{"name":"A deck","investigator_code":"01001",'
        '"slots":{"01006":1},"sideSlots":[]}',
        id: 40838,
      );
      expect(deck.source, const ImportedSource(40838));
      expect(deck.id, 'arkhamdb:40838');
      expect(deck.isImported, isTrue);
      expect(deck.cardCount, 1);
    });

    test('rejects a response missing its investigator', () {
      // A missing name or investigator is not a deck, and must not decode into
      // an empty one.
      expect(
        decode('{"name":"No investigator","slots":{"01006":1}}'),
        throwsA(const ArkhamDBMalformed()),
      );
    });

    test('rejects a response whose main deck is not an object', () {
      expect(
        decode('{"name":"No slots","investigator_code":"01001","slots":[]}'),
        throwsA(const ArkhamDBMalformed()),
      );
    });
  });

  group('errors', () {
    test('unknown id is not found', () {
      // An unknown id answers 200 with an empty body, not 404. Verified
      // against ids 52000 and 99999999. This is the ordinary "no such deck"
      // path, so it has to read as one.
      expect(serving('').decklist(52000), throwsA(const DecklistNotFound()));
    });

    test('a non-positive id never reaches the network', () {
      var called = false;
      final client = ArkhamDBClient(
        fetch: (_) async {
          called = true;
          return (statusCode: 200, body: '');
        },
      );
      expect(client.decklist(0), throwsA(const DecklistNotFound()));
      expect(called, isFalse);
    });

    test('a server error names its status', () {
      expect(
        serving('', statusCode: 500).decklist(1),
        throwsA(const ArkhamDBServerError(500)),
      );
    });

    test('an unreachable host reads as unreachable', () {
      final client = ArkhamDBClient(
        fetch: (_) async => throw const SocketExceptionStub(),
      );
      expect(client.decklist(1), throwsA(isA<ArkhamDBUnreachable>()));
    });

    test('a body that is not a decklist is malformed', () {
      expect(
        serving('this is not json').decklist(1),
        throwsA(const ArkhamDBMalformed()),
      );
    });

    test('every error has a message', () {
      // Every failure says something a person can act on.
      const errors = [
        DecklistNotFound(),
        ArkhamDBUnreachable('offline'),
        ArkhamDBServerError(500),
        ArkhamDBMalformed(),
      ];
      for (final error in errors) {
        expect(error.message, isNotEmpty);
      }
    });

    test('the request goes to the decklist endpoint, not the deck one', () {
      // `/api/public/deck/{id}` answers 302 to the login page for anyone
      // else's deck. Only `/decklist/` is public.
      late Uri requested;
      final client = ArkhamDBClient(
        fetch: (url) async {
          requested = url;
          return (statusCode: 200, body: '{"name":"A deck",'
              '"investigator_code":"01001","slots":{"01006":1}}');
        },
      );
      return client.decklist(40838).then((_) {
        expect(requested.toString(),
            'https://arkhamdb.com/api/public/decklist/40838');
      });
    });
  });
}

/// Stands in for the `SocketException` a real fetch would throw offline.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
