import Foundation

public enum CaseMode: String, Equatable, CaseIterable {
    case none, lower, upper, title
}

public enum CaseTransformer {
    public static func apply(_ input: String, mode: CaseMode, stripDiacritics: Bool) -> String {
        var s = input
        if stripDiacritics {
            s = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }
        switch mode {
        case .none:  return s
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .title: return titlecased(s)
        }
    }

    private static func titlecased(_ s: String) -> String {
        var result = ""
        var atBoundary = true
        for ch in s {
            if ch.isLetter || ch.isNumber {
                result.append(atBoundary ? Character(ch.uppercased()) : ch)
                atBoundary = false
            } else {
                result.append(ch)
                atBoundary = true
            }
        }
        return result
    }
}
