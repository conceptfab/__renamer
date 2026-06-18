import Foundation

public enum CounterBase: Equatable {
    case decimal, hexLower, hexUpper

    var radix: Int { self == .decimal ? 10 : 16 }
    var uppercase: Bool { self == .hexUpper }
}

public struct CounterSpec: Equatable {
    public var start: Int
    public var step: Int
    public var digits: Int
    public var base: CounterBase

    public init(start: Int = 1, step: Int = 1, digits: Int = 1, base: CounterBase = .decimal) {
        self.start = start
        self.step = step
        self.digits = digits
        self.base = base
    }

    public static func parse(_ arg: String?) throws -> CounterSpec {
        guard let arg, !arg.isEmpty else { return CounterSpec() }

        // Compact form: a run of digits -> digit width.
        if arg.allSatisfy({ $0.isNumber }) {
            return CounterSpec(digits: arg.count)
        }

        var spec = CounterSpec()
        for pair in arg.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else {
                throw TemplateError.badArgument(token: "counter", argument: String(pair))
            }
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "start":
                guard let v = Int(value) else { throw TemplateError.badArgument(token: "counter", argument: value) }
                spec.start = v
            case "step":
                guard let v = Int(value) else { throw TemplateError.badArgument(token: "counter", argument: value) }
                spec.step = v
            case "digits":
                guard let v = Int(value), v >= 0 else { throw TemplateError.badArgument(token: "counter", argument: value) }
                spec.digits = v
            case "base":
                switch value {
                case "d": spec.base = .decimal
                case "x": spec.base = .hexLower
                case "X": spec.base = .hexUpper
                default: throw TemplateError.badArgument(token: "counter", argument: value)
                }
            default:
                throw TemplateError.badArgument(token: "counter", argument: key)
            }
        }
        return spec
    }

    public func format(forIndex index: Int) -> String {
        let value = start + index * step
        let negative = value < 0
        var body = String(abs(value), radix: base.radix, uppercase: base.uppercase)
        if body.count < digits {
            body = String(repeating: "0", count: digits - body.count) + body
        }
        return negative ? "-" + body : body
    }
}
