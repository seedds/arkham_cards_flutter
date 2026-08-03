import 'dart:io';

import 'package:arkham_cards/models/card_database.dart';
import 'package:arkham_cards/models/deck.dart';

/// The real bundled data, loaded once for the whole run.
///
/// These tests run against `assets/`, not against fixtures, for the same
/// reason the Swift ones did: their value is catching a schema drift in
/// arkhamdb-json-data, which a fixture would hide.
///
/// Read straight off disk rather than through `rootBundle`, so the model tests
/// stay plain Dart and need no widget binding.
final CardDatabase database = CardDatabase.fromJson(
  File('assets/cards.json').readAsStringSync(),
);

final List<Deck> starters = Deck.parseBundledStarters(
  File('assets/decks.json').readAsStringSync(),
);

/// Where the transcoded card art lives.
const imageDirectory = 'assets/CardImages';
