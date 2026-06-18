import XCTest
@testable import RenamerCore

final class CounterSpecTests: XCTestCase {
    func test_defaultStartsAtOne() throws {
        let c = try CounterSpec.parse(nil)
        XCTAssertEqual(c.format(forIndex: 0), "1")
        XCTAssertEqual(c.format(forIndex: 1), "2")
    }

    func test_compactDigitsForm() throws {
        let c = try CounterSpec.parse("001")
        XCTAssertEqual(c.format(forIndex: 0), "001")
        XCTAssertEqual(c.format(forIndex: 9), "010")
    }

    func test_fullForm() throws {
        let c = try CounterSpec.parse("start=10,step=5,digits=2")
        XCTAssertEqual(c.format(forIndex: 0), "10")
        XCTAssertEqual(c.format(forIndex: 1), "15")
        XCTAssertEqual(c.format(forIndex: 18), "100")
    }

    func test_hexUpper() throws {
        let c = try CounterSpec.parse("start=10,digits=2,base=X")
        XCTAssertEqual(c.format(forIndex: 0), "0A")
        XCTAssertEqual(c.format(forIndex: 5), "0F")
    }

    func test_badPairThrows() {
        XCTAssertThrowsError(try CounterSpec.parse("start=abc"))
    }
}
