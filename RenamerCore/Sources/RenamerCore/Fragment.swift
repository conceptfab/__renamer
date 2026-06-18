import Foundation

/// A 1-indexed, inclusive substring selector. Negative positions count from
/// the end (-1 == last character). `end == nil` means "to the end".
public struct Fragment: Equatable {
    public let start: Int
    public let end: Int?

    public init(start: Int, end: Int?) {
        self.start = start
        self.end = end
    }

    /// Returns nil when `arg` is not a fragment expression (e.g. "upper").
    public static func tryParse(_ arg: String) -> Fragment? {
        let chars = Array(arg)
        guard !chars.isEmpty else { return nil }
        // Find the separating '-': the first '-' that follows a digit.
        var sep: Int? = nil
        for k in 1..<chars.count where chars[k] == "-" && chars[k - 1].isNumber {
            sep = k; break
        }
        if let s = sep {
            let left = String(chars[0..<s])
            let right = String(chars[(s + 1)...])
            guard let start = Int(left) else { return nil }
            if right.isEmpty { return Fragment(start: start, end: nil) }
            guard let end = Int(right) else { return nil }
            return Fragment(start: start, end: end)
        } else {
            guard let single = Int(arg) else { return nil }
            return Fragment(start: single, end: nil)
        }
    }

    public static func parse(_ arg: String) throws -> Fragment {
        guard let f = tryParse(arg) else {
            throw TemplateError.badArgument(token: "fragment", argument: arg)
        }
        return f
    }

    public func apply(to value: String) -> String {
        let chars = Array(value)
        let count = chars.count
        guard count > 0 else { return "" }

        func resolve(_ pos: Int) -> Int {
            // 1-indexed -> 0-indexed; negatives count from end.
            pos > 0 ? pos - 1 : count + pos
        }

        let lo = resolve(start)
        let hi = end.map(resolve) ?? (count - 1)
        let clampedLo = max(0, lo)
        let clampedHi = min(count - 1, hi)
        guard clampedLo <= clampedHi else { return "" }
        return String(chars[clampedLo...clampedHi])
    }
}
