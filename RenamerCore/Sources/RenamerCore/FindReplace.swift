import Foundation

public enum FindReplaceError: Error, Equatable {
    case invalidRegex(String)
}

public struct FindReplace: Equatable, Codable {
    public var search: String
    public var replacement: String
    public var isRegex: Bool
    public var caseSensitive: Bool

    public init(search: String, replacement: String, isRegex: Bool, caseSensitive: Bool) {
        self.search = search
        self.replacement = replacement
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
    }

    public func apply(to input: String) throws -> String {
        guard !search.isEmpty else { return input }

        if isRegex {
            var options: NSRegularExpression.Options = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: search, options: options)
            } catch {
                throw FindReplaceError.invalidRegex(search)
            }
            let range = NSRange(input.startIndex..., in: input)
            return regex.stringByReplacingMatches(in: input, options: [], range: range,
                                                  withTemplate: replacement)
        } else {
            var options: String.CompareOptions = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            return input.replacingOccurrences(of: search, with: replacement, options: options)
        }
    }
}
