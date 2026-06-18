import Foundation

public protocol FileSystemProbe {
    func exists(_ url: URL) -> Bool
}

public struct DefaultFileSystemProbe: FileSystemProbe {
    public init() {}
    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
