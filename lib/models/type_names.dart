/// A card type's name as the game prints it.
///
/// Separate from the styling in `views/faction_style.dart` because
/// `DeckContents` needs the name to title a section and must not depend on the
/// widget layer to get it.
String typeName(String type) => switch (type) {
  'investigator' => 'Investigator',
  'asset' => 'Asset',
  'event' => 'Event',
  'skill' => 'Skill',
  'enemy' => 'Enemy',
  'treachery' => 'Treachery',
  'location' => 'Location',
  'enemy_location' => 'Enemy-Location',
  'act' => 'Act',
  'agenda' => 'Agenda',
  'scenario' => 'Scenario',
  'story' => 'Story',
  'key' => 'Key',
  _ => _capitalized(type),
};

String _capitalized(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
