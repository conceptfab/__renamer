import Foundation

public enum FindReplaceError: Error, Equatable {
    case invalidRegex(String)
    /// Matching ran past its deadline (e.g. catastrophic backtracking) or was cancelled.
    case timedOut
}

public struct FindReplace: Equatable, Codable, Sendable {
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

    /// Compiles the search once so it can be applied to many names.
    public func compiled() throws -> Compiled {
        guard isRegex, !search.isEmpty else { return Compiled(find: self, regex: nil) }
        var options: NSRegularExpression.Options = []
        if !caseSensitive { options.insert(.caseInsensitive) }
        do {
            return Compiled(find: self, regex: try NSRegularExpression(pattern: search, options: options))
        } catch {
            throw FindReplaceError.invalidRegex(search)
        }
    }

    /// A find/replace with its regex compiled.
    public struct Compiled {
        let find: FindReplace
        let regex: NSRegularExpression?

        /// Replaces every match with `replacement` (regex mode: a template, `$1` etc.).
        /// `shouldStop` is polled while a long regex match runs; returning true aborts
        /// it with `FindReplaceError.timedOut`.
        public func apply(to input: String, replacement: String,
                          shouldStop: () -> Bool = { false }) throws -> String {
            guard !find.search.isEmpty else { return input }
            guard let regex else {
                var options: String.CompareOptions = []
                if !find.caseSensitive { options.insert(.caseInsensitive) }
                return input.replacingOccurrences(of: find.search, with: replacement, options: options)
            }

            var matches: [NSTextCheckingResult] = []
            var aborted = false
            let range = NSRange(input.startIndex..., in: input)
            // .reportProgress calls the block periodically during long matches, which is
            // the only way to interrupt a runaway (catastrophically backtracking) pattern.
            regex.enumerateMatches(in: input, options: [.reportProgress], range: range) { match, _, stop in
                if let match { matches.append(match) }
                if shouldStop() {
                    aborted = true
                    stop.pointee = true
                }
            }
            if aborted { throw FindReplaceError.timedOut }

            // Same result as stringByReplacingMatches(in:options:range:withTemplate:).
            let ns = input as NSString
            var out = ""
            var last = 0
            for match in matches {
                out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                out += regex.replacementString(for: match, in: input, offset: 0, template: replacement)
                last = NSMaxRange(match.range)
            }
            out += ns.substring(from: last)
            return out
        }
    }
}
