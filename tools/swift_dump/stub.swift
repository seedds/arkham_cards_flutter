// TypeStyle lives in the SwiftUI layer; DeckContents needs only this from it.
enum TypeStyle {
    static func name(for type: String) -> String {
        switch type {
        case "investigator": return "Investigator"
        case "asset": return "Asset"
        case "event": return "Event"
        case "skill": return "Skill"
        case "enemy": return "Enemy"
        case "treachery": return "Treachery"
        case "location": return "Location"
        case "enemy_location": return "Enemy-Location"
        case "act": return "Act"
        case "agenda": return "Agenda"
        case "scenario": return "Scenario"
        case "story": return "Story"
        case "key": return "Key"
        default: return type.capitalized
        }
    }
}
