import XCTest
@testable import RenamerCore

final class FragmentTests: XCTestCase {
    func test_explicitRange() throws {
        XCTAssertEqual(try Fragment.parse("2-4").apply(to: "abcdef"), "bcd")
    }

    func test_startToEnd() throws {
        XCTAssertEqual(try Fragment.parse("3-").apply(to: "abcdef"), "cdef")
    }

    func test_lastThreeViaNegativeRange() throws {
        XCTAssertEqual(try Fragment.parse("-3-").apply(to: "abcdef"), "def")
    }

    func test_lastThreeShorthand() throws {
        XCTAssertEqual(try Fragment.parse("-3").apply(to: "abcdef"), "def")
    }

    func test_singleNumberIsStartToEnd() throws {
        XCTAssertEqual(try Fragment.parse("5").apply(to: "abcdef"), "ef")
    }

    func test_negativeRangeBothEnds() throws {
        XCTAssertEqual(try Fragment.parse("-3--2").apply(to: "abcdef"), "de")
    }

    func test_outOfRangeClampsToEmpty() throws {
        XCTAssertEqual(try Fragment.parse("10-20").apply(to: "abc"), "")
    }

    func test_nonNumericIsNotAFragment() {
        XCTAssertNil(Fragment.tryParse("upper"))
    }
}
