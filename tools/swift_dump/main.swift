import Foundation

// The same dump as tools/dump_dart.dart, from the Swift models, so the two can
// be diffed. Built against the real model files rather than a copy of them.

let searches = [
    "", "a", "the", "roland", "roland banks", "shotgun", "SHOTGUN",
    "luis", "andre", "ch\u{0153}ur", "choeur", "hunter", "hunter's hunger",
    "heretic", "deduction", "physical training", "e", "of the",
]

let resources = URL(fileURLWithPath: CommandLine.arguments[1])

let cardsData = try Data(contentsOf: resources.appending(path: "cards.json"))
let cards = try JSONDecoder().decode([Card].self, from: cardsData)
let database = CardDatabase(cards: cards)

var out = ""

out += "## order\n"
for card in database.all { out += card.code + "\n" }

out += "## printings\n"
for card in database.all {
    let group = database.printings(of: card)
    guard group.first?.code == card.code else { continue }
    out += "\(card.code): \(group.map(\.code).joined(separator: ","))\n"
}

out += "## search\n"
for term in searches {
    var query = CardQuery()
    query.searchText = term
    let results = database.cards(matching: query)
    let encoded = String(
        data: try JSONEncoder().encode(term), encoding: .utf8
    )!
    out += "\(encoded): \(results.count) "
    out += results.prefix(20).map(\.code).joined(separator: ",") + "\n"
}

out += "## filters\n"
for faction in database.factions {
    var query = CardQuery()
    query.factions = [faction]
    out += "faction \(faction): \(database.count(matching: query))\n"
}
for type in database.types {
    var query = CardQuery()
    query.types = [type]
    out += "type \(type): \(database.count(matching: query))\n"
}
for level in database.levels {
    var query = CardQuery()
    query.levels = [level]
    out += "level \(level): \(database.count(matching: query))\n"
}
for cycle in database.cycles {
    var query = CardQuery()
    query.cycles = [cycle.code]
    out += "cycle \(cycle.code): \(database.count(matching: query))\n"
}
for deck in CardQuery.Deck.allCases {
    var query = CardQuery()
    query.deck = deck
    out += "deck \(deck.rawValue): \(database.count(matching: query))\n"
}
var pair = CardQuery()
pair.factions = ["guardian", "seeker"]
out += "guardian+seeker: \(database.count(matching: pair))\n"
var triple = CardQuery()
triple.factions = ["guardian"]
triple.types = ["asset"]
triple.levels = [0]
out += "guardian asset level 0: \(database.count(matching: triple))\n"

out += "## decks\n"
struct StarterRecord: Decodable {
    let packCode: String
    let name: String
    let investigatorCode: String
    let slots: [String: Int]

    enum CodingKeys: String, CodingKey {
        case name, slots
        case packCode = "pack_code"
        case investigatorCode = "investigator_code"
    }
}
let decksData = try Data(contentsOf: resources.appending(path: "decks.json"))
for record in try JSONDecoder().decode([StarterRecord].self, from: decksData) {
    let deck = Deck(
        source: .starter(packCode: record.packCode),
        name: record.name,
        investigatorCode: record.investigatorCode,
        slots: record.slots,
        sideSlots: [:]
    )
    let contents = DeckContents(deck: deck, database: database)
    out += "\(deck.id) \(deck.name) \(contents.cardCount)\n"
    for section in contents.sections {
        out += "  \(section.typeCode) \(section.cardCount)\n"
        for entry in section.entries {
            out += "    \(entry.quantity) \(entry.card.code) \(entry.card.name)\n"
        }
    }
    out += "  page \(contents.pageSequence.map(\.code).joined(separator: ","))\n"
}

print(out, terminator: "")
