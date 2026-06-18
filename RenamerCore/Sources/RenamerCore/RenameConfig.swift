import Foundation

public struct RenameConfig: Equatable, Codable {
    public var template: String
    public var find: FindReplace
    public var nameCase: CaseMode
    public var extCase: CaseMode
    public var stripDiacritics: Bool
    public var lockExtension: Bool

    public init(template: String, find: FindReplace, nameCase: CaseMode,
                extCase: CaseMode, stripDiacritics: Bool, lockExtension: Bool = false) {
        self.template = template
        self.find = find
        self.nameCase = nameCase
        self.extCase = extCase
        self.stripDiacritics = stripDiacritics
        self.lockExtension = lockExtension
    }
}
