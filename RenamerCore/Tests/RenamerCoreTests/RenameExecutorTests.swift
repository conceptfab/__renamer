import XCTest
@testable import RenamerCore

final class RenameExecutorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("renamer-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private func read(_ name: String) -> String? {
        try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }

    func test_simpleRename() throws {
        let a = try write("a.txt", "A")
        let moves = [Move(from: a, to: dir.appendingPathComponent("b.txt"))]
        let result = try RenameExecutor().execute(moves, overwrite: false)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(read("b.txt"), "A")
        XCTAssertNil(read("a.txt"))
    }

    func test_swapCycle() throws {
        let a = try write("a.txt", "A")
        let b = try write("b.txt", "B")
        let moves = [
            Move(from: a, to: dir.appendingPathComponent("b.txt")),
            Move(from: b, to: dir.appendingPathComponent("a.txt")),
        ]
        let result = try RenameExecutor().execute(moves, overwrite: false)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(read("a.txt"), "B")
        XCTAssertEqual(read("b.txt"), "A")
    }

    func test_caseOnlyRename() throws {
        let a = try write("file.txt", "X")
        let moves = [Move(from: a, to: dir.appendingPathComponent("FILE.TXT"))]
        let result = try RenameExecutor().execute(moves, overwrite: false)
        XCTAssertTrue(result.failures.isEmpty)
        // Read back via case-exact directory listing.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains("FILE.TXT"))
    }

    func test_undoRestoresOriginalNames() throws {
        let a = try write("a.txt", "A")
        let b = try write("b.txt", "B")
        let moves = [
            Move(from: a, to: dir.appendingPathComponent("x.txt")),
            Move(from: b, to: dir.appendingPathComponent("y.txt")),
        ]
        let result = try RenameExecutor().execute(moves, overwrite: false)
        try result.undo.undo()
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertEqual(read("b.txt"), "B")
        XCTAssertNil(read("x.txt"))
    }
}
