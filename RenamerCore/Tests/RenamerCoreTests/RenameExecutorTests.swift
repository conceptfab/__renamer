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

    func test_targetExistsWithoutOverwrite_restoresOriginal() throws {
        let a = try write("a.txt", "A")
        _ = try write("b.txt", "EXISTING")
        let moves = [Move(from: a, to: dir.appendingPathComponent("b.txt"))]
        let result = try RenameExecutor().execute(moves, overwrite: false)

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.message, "Cel istnieje")
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertEqual(read("b.txt"), "EXISTING")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".renamer-tmp-") })
        XCTAssertTrue(result.successfulRenames.isEmpty)
        XCTAssertTrue(result.undo.moves.isEmpty)
    }

    func test_targetExistsWithOverwrite_trashesAndRenames() throws {
        let a = try write("a.txt", "A")
        _ = try write("b.txt", "OLD")
        let moves = [Move(from: a, to: dir.appendingPathComponent("b.txt"))]
        let result = try RenameExecutor().execute(moves, overwrite: true)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(read("b.txt"), "A")
        XCTAssertNil(read("a.txt"))
        XCTAssertEqual(result.successfulRenames, [Move(from: a, to: dir.appendingPathComponent("b.txt"))])
    }

    func test_partialFailure_reportsOnlyActualSuccesses() throws {
        let a = try write("a.txt", "A")
        let b = try write("b.txt", "B")
        _ = try write("c.txt", "EXISTING")
        let moves = [
            Move(from: a, to: dir.appendingPathComponent("x.txt")),
            Move(from: b, to: dir.appendingPathComponent("c.txt")),
        ]
        let result = try RenameExecutor().execute(moves, overwrite: false)

        XCTAssertEqual(result.successfulRenames.count, 1)
        XCTAssertEqual(result.successfulRenames.first?.to.lastPathComponent, "x.txt")
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(read("x.txt"), "A")
        XCTAssertEqual(read("b.txt"), "B")
        XCTAssertEqual(read("c.txt"), "EXISTING")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".renamer-tmp-") })
    }
}
