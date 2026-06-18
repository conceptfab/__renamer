import Foundation

/// The set of variables the user may use in a template.
public enum TokenName: String, Equatable {
    case name, ext, counter, date, time, parent
}

/// A single `{name}` or `{name:argument}` occurrence.
public struct TokenSpec: Equatable {
    public let name: TokenName
    public let argument: String?
    public init(name: TokenName, argument: String?) {
        self.name = name
        self.argument = argument
    }
}

/// A template parsed into a sequence of literal text and tokens.
public enum TemplateSegment: Equatable {
    case literal(String)
    case token(TokenSpec)
}

public enum TemplateError: Error, Equatable {
    case unknownToken(String)
    case unterminatedToken
    case badArgument(token: String, argument: String)
}
