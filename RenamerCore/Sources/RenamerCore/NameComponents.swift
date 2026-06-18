import Foundation

/// A filename split into its base and extension parts.
public struct NameComponents: Equatable {
    public let base: String
    public let ext: String
    public let hadDot: Bool

    public init(base: String, ext: String, hadDot: Bool) {
        self.base = base
        self.ext = ext
        self.hadDot = hadDot
    }

    public init(fullName: String) {
        // A leading dot never starts an extension.
        if let dot = fullName.lastIndex(of: "."), dot != fullName.startIndex {
            self.base = String(fullName[fullName.startIndex..<dot])
            self.ext = String(fullName[fullName.index(after: dot)...])
            self.hadDot = true
        } else {
            self.base = fullName
            self.ext = ""
            self.hadDot = false
        }
    }

    public var fullName: String {
        hadDot ? "\(base).\(ext)" : base
    }
}
