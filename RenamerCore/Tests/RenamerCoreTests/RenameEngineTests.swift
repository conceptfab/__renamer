import XCTest
@testable import RenamerCore

final class RenameEngineTests: XCTestCase {
    func test_buildAndApplyOnDisk() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("engine-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for n in ["IMG_1.jpg", "IMG_2.jpg"] {
            try "x".write(to: dir.appendingPathComponent(n), atomically: true, encoding: .utf8)
        }

        let engine = RenameEngine()
        let items = FileItemLoader.load([dir.appendingPathComponent("IMG_1.jpg"),
                                         dir.appendingPathComponent("IMG_2.jpg")])
        let cfg = RenameConfig(template: "photo_{counter:01}.{ext}",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)

        let rows = engine.plan(items: items, config: cfg)
        XCTAssertEqual(rows.map(\.proposedName), ["photo_01.jpg", "photo_02.jpg"])

        let result = try engine.apply(rows: rows, overwrite: false)
        XCTAssertTrue(result.failures.isEmpty)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        XCTAssertEqual(names, ["photo_01.jpg", "photo_02.jpg"])
    }
}
