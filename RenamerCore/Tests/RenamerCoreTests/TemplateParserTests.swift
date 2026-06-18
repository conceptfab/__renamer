import XCTest
@testable import RenamerCore

final class TemplateParserTests: XCTestCase {
    func test_plainTextIsOneLiteral() throws {
        XCTAssertEqual(try TemplateParser.parse("hello"), [.literal("hello")])
    }

    func test_tokenWithoutArgument() throws {
        XCTAssertEqual(
            try TemplateParser.parse("{name}"),
            [.token(TokenSpec(name: .name, argument: nil))]
        )
    }

    func test_tokenWithArgument() throws {
        XCTAssertEqual(
            try TemplateParser.parse("{counter:001}"),
            [.token(TokenSpec(name: .counter, argument: "001"))]
        )
    }

    func test_mixedLiteralAndTokens() throws {
        XCTAssertEqual(
            try TemplateParser.parse("a_{name}.{ext}"),
            [.literal("a_"),
             .token(TokenSpec(name: .name, argument: nil)),
             .literal("."),
             .token(TokenSpec(name: .ext, argument: nil))]
        )
    }

    func test_escapedBraces() throws {
        XCTAssertEqual(try TemplateParser.parse("{{x}}"), [.literal("{x}")])
    }

    func test_unknownTokenThrows() {
        XCTAssertThrowsError(try TemplateParser.parse("{bogus}")) { error in
            XCTAssertEqual(error as? TemplateError, .unknownToken("bogus"))
        }
    }

    func test_unterminatedTokenThrows() {
        XCTAssertThrowsError(try TemplateParser.parse("{name")) { error in
            XCTAssertEqual(error as? TemplateError, .unterminatedToken)
        }
    }
}
