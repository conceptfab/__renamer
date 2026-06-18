import Foundation

public enum TemplateParser {
    public static func parse(_ template: String) throws -> [TemplateSegment] {
        var segments: [TemplateSegment] = []
        var literal = ""
        let chars = Array(template)
        var i = 0

        func flushLiteral() {
            if !literal.isEmpty {
                segments.append(.literal(literal))
                literal = ""
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c == "{" {
                if i + 1 < chars.count, chars[i + 1] == "{" {
                    literal.append("{"); i += 2; continue
                }
                // Read until closing '}'.
                var body = ""
                var j = i + 1
                var closed = false
                while j < chars.count {
                    if chars[j] == "}" { closed = true; break }
                    body.append(chars[j]); j += 1
                }
                guard closed else { throw TemplateError.unterminatedToken }
                flushLiteral()
                segments.append(.token(try makeToken(from: body)))
                i = j + 1
            } else if c == "}" {
                if i + 1 < chars.count, chars[i + 1] == "}" {
                    literal.append("}"); i += 2; continue
                }
                literal.append("}"); i += 1
            } else {
                literal.append(c); i += 1
            }
        }
        flushLiteral()
        return segments
    }

    private static func makeToken(from body: String) throws -> TokenSpec {
        let parts = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let rawName = String(parts[0])
        guard let name = TokenName(rawValue: rawName) else {
            throw TemplateError.unknownToken(rawName)
        }
        let argument = parts.count > 1 ? String(parts[1]) : nil
        return TokenSpec(name: name, argument: argument)
    }
}
