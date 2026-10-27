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
        stored() ?? []
    }

    /// Stored data none of which could be read (e.g. a newer format) is kept under
    /// `renamer.presets.unreadable` before the first overwrite.
    func save(_ presets: [Preset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        if stored() == nil, defaults.data(forKey: backupKey) == nil {
            defaults.set(defaults.data(forKey: key), forKey: backupKey)
        }
        defaults.set(data, forKey: key)
    }

    private var backupKey: String { key + ".unreadable" }

    /// Readable presets; an unreadable entry is skipped. nil: data exists but nothing in it decodes.
    private func stored() -> [Preset]? {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let entries = try? JSONDecoder().decode([Failable].self, from: data) else { return nil }
        let presets = entries.compactMap(\.preset)
        return presets.isEmpty && !entries.isEmpty ? nil : presets
    }

    private struct Failable: Decodable {
        let preset: Preset?
        init(from decoder: Decoder) throws { preset = try? Preset(from: decoder) }
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
