import Foundation
import RenamerCore

/// Persists the user's presets as JSON in UserDefaults.
struct PresetStore {
    private let defaults = UserDefaults.standard
    private let key = "renamer.presets"

    func load() -> [Preset] {
        guard let data = defaults.data(forKey: key),
              let presets = try? JSONDecoder().decode([Preset].self, from: data) else {
            return []
        }
        return presets
    }

    func save(_ presets: [Preset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}
