import Foundation

public protocol FileSystemProbe {
    func exists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
}

public extension FileSystemProbe {
    func isDirectory(_ url: URL) -> Bool { false }
}

public struct DefaultFileSystemProbe: FileSystemProbe {
    public init() {}
    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    public func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
