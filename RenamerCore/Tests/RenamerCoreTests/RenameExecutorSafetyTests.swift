import XCTest
@testable import RenamerCore

final class RenameExecutorSafetyTests: XCTestCase {
    private var root: URL!
    private var dir: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("renamer-safety-" + UUID().uuidString)
        dir = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }
    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private func read(_ name: String) -> String? {
        try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
    }
    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    func test_targetOutsideSourceDirectoryFails() throws {
        let a = try write("a.txt", "A")
        let moves = [Move(from: a, to: dir.appendingPathComponent("..")),
                     Move(from: a, to: dir.appendingPathComponent("."))]
        let result = try RenameExecutor().execute(moves, overwrite: true)
        XCTAssertEqual(result.failures.count, 2)
        XCTAssertTrue(result.successfulRenames.isEmpty)
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertEqual(try names(), ["a.txt"])
    }

    func test_existingFolderIsNeverTrashed() throws {
        let a = try write("a.txt", "A")
        let folder = dir.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = try RenameExecutor().execute([Move(from: a, to: folder)], overwrite: true)
        XCTAssertEqual(result.failures.count, 1)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertFalse(try names().contains { $0.hasPrefix(".renamer-tmp-") })
    }

    func test_undoRestoresTrashedFile() throws {
        let a = try write("a.txt", "A")
        _ = try write("b.txt", "OLD")
        let result = try RenameExecutor().execute([Move(from: a, to: dir.appendingPathComponent("b.txt"))],
                                                  overwrite: true)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.undo.trashed.count, 1)
        let outcome = result.undo.undo()
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertTrue(outcome.remaining.isEmpty)
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertEqual(read("b.txt"), "OLD")
    }

    func test_undoIsBestEffortPerFile() throws {
        let a = try write("a.txt", "A")
        let b = try write("b.txt", "B")
        let result = try RenameExecutor().execute([
            Move(from: a, to: dir.appendingPathComponent("x.txt")),
            Move(from: b, to: dir.appendingPathComponent("y.txt")),
        ], overwrite: false)
        XCTAssertTrue(result.failures.isEmpty)

        // Something now occupies a.txt, so x.txt cannot go back.
        _ = try write("a.txt", "BLOCKER")
        let first = result.undo.undo()
        XCTAssertEqual(first.failures.count, 1)
        XCTAssertEqual(first.restored, [Move(from: dir.appendingPathComponent("y.txt"), to: b)])
        XCTAssertEqual(read("b.txt"), "B")
        XCTAssertEqual(read("x.txt"), "A", "a file that cannot go back stays at its visible name")
        XCTAssertEqual(read("a.txt"), "BLOCKER")
        XCTAssertFalse(try names().contains { $0.hasPrefix(".renamer-") })
        XCTAssertEqual(first.remaining.moves.count, 1)

        // Retrying only replays what is left.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.txt"))
        let second = first.remaining.undo()
        XCTAssertTrue(second.failures.isEmpty)
        XCTAssertTrue(second.remaining.isEmpty)
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertEqual(try names(), ["a.txt", "b.txt"])
    }

    func test_undoSwapCycle() throws {
        let a = try write("a.txt", "A")
        let b = try write("b.txt", "B")
        let result = try RenameExecutor().execute([
            Move(from: a, to: dir.appendingPathComponent("b.txt")),
            Move(from: b, to: dir.appendingPathComponent("a.txt")),
        ], overwrite: false)
        let outcome = result.undo.undo()
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertEqual(read("b.txt"), "B")
        XCTAssertEqual(try names(), ["a.txt", "b.txt"])
    }

    func test_tempNameKeepsOriginalAndFits() {
        let short = RenameExecutor.tempName(for: "zdjęcie.jpg")
        XCTAssertTrue(short.hasPrefix(".renamer-tmp-"))
        XCTAssertTrue(short.hasSuffix("-zdjęcie.jpg"))
        let long = RenameExecutor.tempName(for: String(repeating: "ż", count: 127) + ".j")
        XCTAssertLessThanOrEqual(long.utf8.count, 255)
        XCTAssertTrue(long.hasPrefix(".renamer-tmp-"))
        XCTAssertTrue(long.contains("żżż"))
    }
}
