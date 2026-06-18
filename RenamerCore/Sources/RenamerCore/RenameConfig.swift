import Foundation

public struct RenameConfig: Equatable {
    public var template: String
    public var find: FindReplace
    public var nameCase: CaseMode
    public var extCase: CaseMode
    public var stripDiacritics: Bool

    public init(template: String, find: FindReplace, nameCase: CaseMode,
                extCase: CaseMode, stripDiacritics: Bool) {
        self.template = template
        self.find = find
        self.nameCase = nameCase
        self.extCase = extCase
        self.stripDiacritics = stripDiacritics
    }
}
