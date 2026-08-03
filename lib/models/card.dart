/// One card, matching a record of the bundled `cards.json`.
///
/// The fields are upstream's, so the names are upstream's too. The build
/// script has already settled the quirks that would otherwise need branches
/// here: a reprint's missing name and type are filled in from the card it
/// reprints, and the two forms of card back -- a `<code>b` image and a
/// separate `back_link` record -- are collapsed into one `back_image`.
library;

/// A numeric card field, which upstream encodes with negative sentinels.
///
/// The table is arkhamdb-json-data's: `-2` is X, `-3` is `*`, `-4` is `?`, and
/// a JSON `null` is a printed dash. Anything else -- including `-1`, which is
/// not a sentinel -- is the number itself.
sealed class CardValue {
  const CardValue();

  /// Reads a value that is already known to be present.
  ///
  /// A `null` here means the key was present and null, which is a printed
  /// dash. The caller distinguishes that from an absent key, which means the
  /// field is not printed on this card at all -- see [Card.readValue].
  factory CardValue.fromJson(Object? json) {
    if (json == null) return const CardDash();
    final number = json as int;
    return switch (number) {
      -2 => const CardVariable(),
      -3 => const CardStarred(),
      -4 => const CardUnknown(),
      _ => CardNumber(number),
    };
  }

  /// What the card prints.
  String get display;

  /// The value as a plain count, treating every non-numeric form as zero.
  int get number => 0;
}

class CardNumber extends CardValue {
  const CardNumber(this.value);

  final int value;

  @override
  String get display => '$value';

  @override
  int get number => value;

  @override
  bool operator ==(Object other) => other is CardNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class CardVariable extends CardValue {
  const CardVariable();

  @override
  String get display => 'X';

  @override
  bool operator ==(Object other) => other is CardVariable;

  @override
  int get hashCode => 'X'.hashCode;
}

class CardStarred extends CardValue {
  const CardStarred();

  @override
  String get display => '*';

  @override
  bool operator ==(Object other) => other is CardStarred;

  @override
  int get hashCode => '*'.hashCode;
}

class CardUnknown extends CardValue {
  const CardUnknown();

  @override
  String get display => '?';

  @override
  bool operator ==(Object other) => other is CardUnknown;

  @override
  int get hashCode => '?'.hashCode;
}

class CardDash extends CardValue {
  const CardDash();

  /// An en dash, as printed.
  @override
  String get display => '\u2013';

  @override
  bool operator ==(Object other) => other is CardDash;

  @override
  int get hashCode => '\u2013'.hashCode;
}

class Card {
  const Card({
    required this.code,
    required this.name,
    required this.typeCode,
    required this.factionCode,
    required this.packCode,
    required this.packName,
    required this.cycleCode,
    required this.cycleName,
    required this.position,
    required this.printedNumber,
    required this.sortKey,
    this.subname,
    this.faction2Code,
    this.faction3Code,
    this.subtypeCode,
    this.text,
    this.flavor,
    this.traits,
    this.backName,
    this.backText,
    this.backFlavor,
    this.cost,
    this.xp,
    this.health,
    this.sanity,
    this.shroud,
    this.clues,
    this.doom,
    this.stage,
    this.victory,
    this.enemyFight,
    this.enemyEvade,
    this.enemyDamage,
    this.enemyHorror,
    this.skillWillpower,
    this.skillIntellect,
    this.skillCombat,
    this.skillAgility,
    this.skillWild,
    this.slot,
    this.isUnique,
    this.permanent,
    this.exceptional,
    this.myriad,
    this.exile,
    this.deckLimit,
    this.quantity,
    this.restrictions,
    this.deckRequirements,
    this.illustrator,
    this.encounterCode,
    this.encounterName,
    this.backLink,
    this.doubleSided,
    this.duplicateOf,
    this.alternateOf,
    this.variantOf,
    this.frontImage,
    this.backImage,
  });

  factory Card.fromJson(Map<String, Object?> json) => Card(
    code: json['code']! as String,
    name: json['name']! as String,
    typeCode: json['type_code']! as String,
    factionCode: json['faction_code']! as String,
    packCode: json['pack_code']! as String,
    packName: json['pack_name']! as String,
    cycleCode: json['cycle_code']! as String,
    cycleName: json['cycle_name']! as String,
    position: json['position']! as int,
    printedNumber: json['printed_number']! as String,
    sortKey: (json['sort_key']! as List<Object?>).cast<int>(),
    subname: json['subname'] as String?,
    faction2Code: json['faction2_code'] as String?,
    faction3Code: json['faction3_code'] as String?,
    subtypeCode: json['subtype_code'] as String?,
    text: json['text'] as String?,
    flavor: json['flavor'] as String?,
    traits: json['traits'] as String?,
    backName: json['back_name'] as String?,
    backText: json['back_text'] as String?,
    backFlavor: json['back_flavor'] as String?,
    cost: readValue(json, 'cost'),
    xp: json['xp'] as int?,
    health: readValue(json, 'health'),
    sanity: readValue(json, 'sanity'),
    shroud: readValue(json, 'shroud'),
    clues: readValue(json, 'clues'),
    doom: readValue(json, 'doom'),
    stage: json['stage'] as int?,
    victory: json['victory'] as int?,
    enemyFight: readValue(json, 'enemy_fight'),
    enemyEvade: readValue(json, 'enemy_evade'),
    enemyDamage: json['enemy_damage'] as int?,
    enemyHorror: json['enemy_horror'] as int?,
    skillWillpower: readValue(json, 'skill_willpower'),
    skillIntellect: readValue(json, 'skill_intellect'),
    skillCombat: readValue(json, 'skill_combat'),
    skillAgility: readValue(json, 'skill_agility'),
    skillWild: json['skill_wild'] as int?,
    slot: json['slot'] as String?,
    isUnique: json['is_unique'] as bool?,
    permanent: json['permanent'] as bool?,
    exceptional: json['exceptional'] as bool?,
    myriad: json['myriad'] as bool?,
    exile: json['exile'] as bool?,
    deckLimit: json['deck_limit'] as int?,
    quantity: json['quantity'] as int?,
    restrictions: json['restrictions'] as String?,
    deckRequirements: json['deck_requirements'] as String?,
    illustrator: json['illustrator'] as String?,
    encounterCode: json['encounter_code'] as String?,
    encounterName: json['encounter_name'] as String?,
    backLink: json['back_link'] as String?,
    doubleSided: json['double_sided'] as bool?,
    duplicateOf: json['duplicate_of'] as String?,
    alternateOf: json['alternate_of'] as String?,
    variantOf: json['variant_of'] as String?,
    frontImage: json['front_image'] as String?,
    backImage: json['back_image'] as String?,
  );

  /// A [CardValue] field, distinguishing an absent key from a null one.
  ///
  /// The distinction is real and three-way: no key means the field is not
  /// printed on this card, a null means a printed dash, and a number means a
  /// number. Testing `json[key] == null` would collapse the first two and turn
  /// every card without a shroud into a card printed with a dash for one.
  static CardValue? readValue(Map<String, Object?> json, String key) =>
      json.containsKey(key) ? CardValue.fromJson(json[key]) : null;

  final String code;
  final String name;
  final String? subname;
  final String typeCode;
  final String factionCode;
  final String? faction2Code;
  final String? faction3Code;
  final String? subtypeCode;
  final String? text;
  final String? flavor;
  final String? traits;
  final String? backName;
  final String? backText;
  final String? backFlavor;
  final CardValue? cost;
  final int? xp;
  final CardValue? health;
  final CardValue? sanity;
  final CardValue? shroud;
  final CardValue? clues;
  final CardValue? doom;
  final int? stage;
  final int? victory;
  final CardValue? enemyFight;
  final CardValue? enemyEvade;
  final int? enemyDamage;
  final int? enemyHorror;
  final CardValue? skillWillpower;
  final CardValue? skillIntellect;
  final CardValue? skillCombat;
  final CardValue? skillAgility;
  final int? skillWild;
  final String? slot;
  final bool? isUnique;
  final bool? permanent;
  final bool? exceptional;
  final bool? myriad;
  final bool? exile;
  final int? deckLimit;
  final int? quantity;
  final String? restrictions;
  final String? deckRequirements;
  final String? illustrator;
  final String packCode;
  final String packName;
  final String cycleCode;
  final String cycleName;
  final String? encounterCode;
  final String? encounterName;
  final int position;

  /// The number printed on the card, which is [position] plus the code's
  /// letter where a box prints two cards at one number.
  ///
  /// 379 positions are shared, so this is what tells `#53a` from `#53b`.
  final String printedNumber;

  final String? backLink;
  final bool? doubleSided;
  final String? duplicateOf;
  final String? alternateOf;
  final String? variantOf;

  /// `[cycle_position, pack_position, position]`, the order the boxes shipped.
  final List<int> sortKey;

  final String? frontImage;
  final String? backImage;

  bool get isPlayerCard => encounterCode == null;

  bool get isInvestigator => typeCode == 'investigator';

  /// Investigator, act and agenda art is stored landscape.
  bool get isLandscape =>
      typeCode == 'investigator' || typeCode == 'act' || typeCode == 'agenda';

  /// Whether tapping the card turns it over.
  ///
  /// 16 cards are two-sided and have no back image in the source dump -- `98004`
  /// Roland Banks among them -- but do carry the back's text. They flip to that
  /// text rather than pretending to be one-sided.
  bool get hasBack => backImage != null || backText != null;

  /// A missing `xp` is level 0, not an unknown level: the signature cards and
  /// the basic weakness omit it because a card you cannot buy has no level.
  int get level => xp ?? 0;

  List<String> get factions =>
      [factionCode, faction2Code, faction3Code].whereType<String>().toList();

  /// Identity is the code alone. Every other field is a property of the card
  /// that code names, so two records sharing one cannot be two cards.
  @override
  bool operator ==(Object other) => other is Card && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Card($code $name)';
}
