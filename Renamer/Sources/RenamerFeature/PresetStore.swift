import Foundation
import RenamerCore

/// Persists the user's presets as JSON in UserDefaults.
struct PresetStore {
    private let defaults: UserDefaults
    private let key = "renamer.presets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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

/// Name and id of a saved preset, for hosts that list presets without opening a session
/// (e.g. the CFAB Control panel).
public struct RenamerPresetInfo: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    /// Presets saved in `defaults` (`renamer.presets`), in their stored order.
    public static func saved(in defaults: UserDefaults) -> [RenamerPresetInfo] {
        PresetStore(defaults: defaults).load().map { RenamerPresetInfo(id: $0.id, name: $0.name) }
    }
}
