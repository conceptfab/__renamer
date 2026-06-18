import Foundation

public enum FileItemLoader {
    public static func load(_ url: URL) throws -> FileItem {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        let date = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        return FileItem(url: url, modificationDate: date)
    }

    public static func load(_ urls: [URL]) -> [FileItem] {
        urls.compactMap { try? load($0) }
    }
}
