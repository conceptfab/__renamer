import XCTest
@testable import RenamerCore

final class LockExtensionTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private let builder = PlanBuilder(evaluator: TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!))

    private func cfg(template: String = "", search: String = "", replacement: String = "",
                     isRegex: Bool = false, nameCase: CaseMode = .none, extCase: CaseMode = .none,
                     lock: Bool) -> RenameConfig {
        RenameConfig(template: template,
                     find: FindReplace(search: search, replacement: replacement, isRegex: isRegex, caseSensitive: true),
                     nameCase: nameCase, extCase: extCase, stripDiacritics: false, lockExtension: lock)
    }

    func test_lockReattachesOriginalExtensionWhenTemplateOmitsIt() throws {
        let name = try builder.proposedName(for: item("/h/IMG_1.jpg"), index: 0,
                                            config: cfg(template: "photo_{counter:001}", lock: true))
        XCTAssertEqual(name, "photo_001.jpg")
    }

    func test_lockForcesOriginalExtensionEvenIfTemplateChangesIt() throws {
        let name = try builder.proposedName(for: item("/h/a.jpeg"), index: 0,
                                            config: cfg(template: "{name}.png", lock: true))
        XCTAssertEqual(name, "a.jpeg")
    }

    func test_lockMakesFindReplaceIgnoreExtension() throws {
        let name = try builder.proposedName(for: item("/h/jpg.jpg"), index: 0,
                                            config: cfg(search: "jpg", replacement: "txt", lock: true))
        XCTAssertEqual(name, "txt.jpg")
    }

    func test_lockWithNoExtensionFile() throws {
        let name = try builder.proposedName(for: item("/h/README"), index: 0,
                                            config: cfg(nameCase: .lower, lock: true))
        XCTAssertEqual(name, "readme")
    }

    func test_lockOffKeepsCurrentBehavior() throws {
        let name = try builder.proposedName(for: item("/h/Report.TXT"), index: 0,
                                            config: cfg(nameCase: .upper, extCase: .lower, lock: false))
        XCTAssertEqual(name, "REPORT.txt")
    }

    func test_lockKeepsDotsThatComeFromTokens() throws {
        let cases: [(file: String, template: String, expected: String)] = [
            ("2024.05.12 urlop.jpg", "{name}_edit", "2024.05.12 urlop_edit.jpg"),
            ("archive.tar.gz", "{name}_v2", "archive.tar_v2.gz"),
            ("IMG_1.jpg", "{counter}. {name}", "1. IMG_1.jpg"),
            ("2024.05.12 urlop.jpg", "{name}.{ext}", "2024.05.12 urlop.jpg"),
            ("2024.05.12 urlop.jpg", "{name}.png", "2024.05.12 urlop.jpg"),
        ]
        for c in cases {
            let name = try builder.proposedName(for: item("/h/" + c.file), index: 0,
                                                config: cfg(template: c.template, lock: true))
            XCTAssertEqual(name, c.expected, "\(c.file) + \(c.template)")
        }
    }
}
