import Foundation

/// Pure operations over a preset list. Each returns a new array.
public enum PresetManager {
    public static func add(_ preset: Preset, to presets: [Preset]) -> [Preset] {
        presets + [preset]
    }

    public static func delete(id: UUID, from presets: [Preset]) -> [Preset] {
        presets.filter { $0.id != id }
    }

    public static func rename(id: UUID, to name: String, in presets: [Preset]) -> [Preset] {
        presets.map { preset in
            guard preset.id == id else { return preset }
            var copy = preset
            copy.name = name
            return copy
        }
    }
}
