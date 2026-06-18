import Foundation

/// A file to be renamed. Holds only what the engine needs so evaluation is
/// pure and does not touch disk.
public struct FileItem: Equatable {
    public let url: URL
    public let modificationDate: Date

    public init(url: URL, modificationDate: Date) {
        self.url = url
        self.modificationDate = modificationDate
    }

    public var fullName: String { url.lastPathComponent }
    public var directory: URL {
        // Normalize so directory URLs match fileURLWithPath without a trailing slash.
        URL(fileURLWithPath: url.deletingLastPathComponent().path)
    }
    public var parentName: String { directory.lastPathComponent }

    private var components: NameComponents { NameComponents(fullName: fullName) }
    public var baseName: String { components.base }
    public var ext: String { components.ext }
}
