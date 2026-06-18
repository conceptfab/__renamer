import Foundation

/// A named, saved rename configuration.
public struct Preset: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var config: RenameConfig

    public init(id: UUID = UUID(), name: String, config: RenameConfig) {
        self.id = id
        self.name = name
        self.config = config
    }
}
