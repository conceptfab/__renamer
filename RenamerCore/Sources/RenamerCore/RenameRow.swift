import Foundation

public enum RowStatus: Equatable {
    case ok, warning, error
}

public struct RenameRow: Equatable {
    public let item: FileItem
    public let proposedName: String
    public var status: RowStatus
    public var message: String?

    public init(item: FileItem, proposedName: String, status: RowStatus, message: String?) {
        self.item = item
        self.proposedName = proposedName
        self.status = status
        self.message = message
    }

    /// Destination URL in the same directory as the source.
    public var targetURL: URL { item.directory.appendingPathComponent(proposedName) }
}
