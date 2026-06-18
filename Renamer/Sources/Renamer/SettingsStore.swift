import Foundation
import RenamerCore

struct SettingsStore {
    struct Snapshot {
        var template: String = ""
        var search: String = ""
        var replacement: String = ""
        var isRegex: Bool = false
        var caseSensitive: Bool = true
        var nameCase: CaseMode = .none
        var extCase: CaseMode = .none
        var stripDiacritics: Bool = false
    }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let template = "renamer.template"
        static let search = "renamer.search"
        static let replacement = "renamer.replacement"
        static let isRegex = "renamer.isRegex"
        static let caseSensitive = "renamer.caseSensitive"
        static let nameCase = "renamer.nameCase"
        static let extCase = "renamer.extCase"
        static let stripDiacritics = "renamer.stripDiacritics"
    }

    func load() -> Snapshot {
        Snapshot(
            template: defaults.string(forKey: Key.template) ?? "",
            search: defaults.string(forKey: Key.search) ?? "",
            replacement: defaults.string(forKey: Key.replacement) ?? "",
            isRegex: defaults.bool(forKey: Key.isRegex),
            caseSensitive: defaults.object(forKey: Key.caseSensitive) as? Bool ?? true,
            nameCase: CaseMode(rawValue: defaults.string(forKey: Key.nameCase) ?? "") ?? .none,
            extCase: CaseMode(rawValue: defaults.string(forKey: Key.extCase) ?? "") ?? .none,
            stripDiacritics: defaults.bool(forKey: Key.stripDiacritics)
        )
    }

    func save(_ snapshot: Snapshot) {
        defaults.set(snapshot.template, forKey: Key.template)
        defaults.set(snapshot.search, forKey: Key.search)
        defaults.set(snapshot.replacement, forKey: Key.replacement)
        defaults.set(snapshot.isRegex, forKey: Key.isRegex)
        defaults.set(snapshot.caseSensitive, forKey: Key.caseSensitive)
        defaults.set(snapshot.nameCase.rawValue, forKey: Key.nameCase)
        defaults.set(snapshot.extCase.rawValue, forKey: Key.extCase)
        defaults.set(snapshot.stripDiacritics, forKey: Key.stripDiacritics)
    }
}

extension CaseMode {
    var label: String {
        switch self {
        case .none: return "Bez zmian"
        case .lower: return "małe litery"
        case .upper: return "WIELKIE LITERY"
        case .title: return "Każde Słowo"
        }
    }
}
