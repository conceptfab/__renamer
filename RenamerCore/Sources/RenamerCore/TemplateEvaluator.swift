import Foundation

public struct TemplateEvaluator {
    private let locale: Locale
    private let timeZone: TimeZone
    /// One DateFormatter per pattern, shared by every file of a plan.
    private let formatters = FormatterCache()

    public init(locale: Locale = Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    public func evaluate(_ segments: [TemplateSegment], item: FileItem, index: Int) throws -> String {
        var out = ""
        for segment in segments {
            switch segment {
            case .literal(let text):
                out += text
            case .token(let spec):
                out += try value(for: spec, item: item, index: index)
            }
        }
        return out
    }

    private func value(for spec: TokenSpec, item: FileItem, index: Int) throws -> String {
        switch spec.name {
        case .name:   return try stringValue(item.baseName, arg: spec.argument)
        case .ext:    return try stringValue(item.ext, arg: spec.argument)
        case .parent: return try stringValue(item.parentName, arg: spec.argument)
        case .counter:
            return try CounterSpec.parse(spec.argument).format(forIndex: index)
        case .date:
            return formattedDate(item.modificationDate, pattern: spec.argument ?? "yyyy-MM-dd")
        case .time:
            return formattedDate(item.modificationDate, pattern: spec.argument ?? "HH-mm-ss")
        }
    }

    private func stringValue(_ base: String, arg: String?) throws -> String {
        guard let arg, !arg.isEmpty else { return base }
        switch arg {
        case "upper": return CaseTransformer.apply(base, mode: .upper, stripDiacritics: false)
        case "lower": return CaseTransformer.apply(base, mode: .lower, stripDiacritics: false)
        case "title": return CaseTransformer.apply(base, mode: .title, stripDiacritics: false)
        default:
            return try Fragment.parse(arg).apply(to: base)
        }
    }

    private func formattedDate(_ date: Date, pattern: String) -> String {
        formatters.formatter(pattern: pattern, locale: locale, timeZone: timeZone).string(from: date)
    }
}

/// Creating a DateFormatter is expensive; cache them by pattern. Locked because the
/// evaluator may be used from a background planning task.
private final class FormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var byPattern: [String: DateFormatter] = [:]

    func formatter(pattern: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = byPattern[pattern] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = pattern
        byPattern[pattern] = f
        return f
    }
}
