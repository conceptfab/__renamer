# RenamerCore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `RenamerCore`, a pure, UI-free Swift package that implements the entire batch-rename engine (token templates, find/replace, case conversion, collision detection, safe execution, undo) — fully unit-tested via `swift test`.

**Architecture:** A standalone SwiftPM library package developed and tested entirely from the command line. The engine is split into focused, single-responsibility files. Evaluation is a deterministic pipeline: `template → find/replace → case`. Filesystem access is isolated behind a `FileSystemProbe` protocol (for collision checks) and confined to the executor/loader (tested against real temp directories). No SwiftUI, AppKit, or Finder code lives here — that is Plan 2.

**Tech Stack:** Swift 5.9+, SwiftPM, XCTest, Foundation (`NSRegularExpression`, `DateFormatter`, `FileManager`). Target platform macOS 13+.

**Reference spec:** `docs/superpowers/specs/2026-06-18-macos-batch-renamer-design.md` (sections 5, 7, 8).

---

## File Structure

```
RenamerCore/
  Package.swift
  Sources/RenamerCore/
    FileItem.swift            # source file model + name/extension splitting
    NameComponents.swift      # split a filename into base + ext (+ hadDot)
    TemplateSegment.swift     # TokenName, TokenSpec, TemplateSegment, TemplateError
    TemplateParser.swift      # String -> [TemplateSegment]
    Fragment.swift            # substring "a-b" parsing + application
    CounterSpec.swift         # counter argument parsing + per-index formatting
    TemplateEvaluator.swift   # [TemplateSegment] + FileItem + index -> String
    FindReplace.swift         # plain + regex search/replace
    CaseTransformer.swift     # CaseMode + diacritics stripping
    RenameConfig.swift        # full user configuration struct
    RenameRow.swift           # RowStatus, RenameRow
    FileSystemProbe.swift     # protocol + default impl
    CollisionDetector.swift   # annotate rows with conflicts/validation
    PlanBuilder.swift         # items + config -> [RenameRow]
    RenameExecutor.swift      # Move, ExecutionResult, MoveFailure, UndoBatch, executor
    FileItemLoader.swift      # load FileItem from disk (reads modification date)
    RenameEngine.swift        # thin façade: build + execute
  Tests/RenamerCoreTests/
    (one test file per source file, same base name + "Tests")
```

Each file has one responsibility. Types are referenced across tasks exactly as defined below — do not rename them.

---

## Task 0: Initialize repository and Swift package

**Files:**
- Create: `.gitignore`
- Create: `RenamerCore/Package.swift`
- Create: `RenamerCore/Sources/RenamerCore/RenamerCore.swift` (placeholder, deleted later)
- Create: `RenamerCore/Tests/RenamerCoreTests/SmokeTests.swift`

- [ ] **Step 1: Initialize git at the repo root**

Run:
```bash
cd /Users/micz/__DEV__/__renamer && git init
```
Expected: `Initialized empty Git repository in /Users/micz/__DEV__/__renamer/.git/`

- [ ] **Step 2: Create `.gitignore`**

Create `.gitignore`:
```gitignore
.DS_Store
.build/
DerivedData/
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
.superpowers/
```

- [ ] **Step 3: Create the package manifest**

Create `RenamerCore/Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RenamerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RenamerCore", targets: ["RenamerCore"])
    ],
    targets: [
        .target(name: "RenamerCore"),
        .testTarget(name: "RenamerCoreTests", dependencies: ["RenamerCore"])
    ]
)
```

- [ ] **Step 4: Create a placeholder source and a smoke test**

Create `RenamerCore/Sources/RenamerCore/RenamerCore.swift`:
```swift
// Placeholder so the target compiles; removed once real types exist.
enum RenamerCorePlaceholder {}
```

Create `RenamerCore/Tests/RenamerCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class SmokeTests: XCTestCase {
    func test_packageCompilesAndTestsRun() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 5: Run the test suite to verify the package builds**

Run:
```bash
cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test
```
Expected: PASS — `Executed 1 test, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add .gitignore RenamerCore
git commit -m "chore: initialize repo and RenamerCore package"
```

---

## Task 1: NameComponents (split filename into base + extension)

Splitting rule: the extension is the text after the **last** dot, but a leading dot does not start an extension (so `.gitignore` has base `.gitignore`, ext ``). No dot → ext is empty. `hadDot` records whether a separating dot existed, so recomposition is exact.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/NameComponents.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/NameComponentsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/NameComponentsTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class NameComponentsTests: XCTestCase {
    func test_splitsBaseAndExtension() {
        let c = NameComponents(fullName: "photo.JPG")
        XCTAssertEqual(c.base, "photo")
        XCTAssertEqual(c.ext, "JPG")
        XCTAssertTrue(c.hadDot)
        XCTAssertEqual(c.fullName, "photo.JPG")
    }

    func test_noExtension() {
        let c = NameComponents(fullName: "README")
        XCTAssertEqual(c.base, "README")
        XCTAssertEqual(c.ext, "")
        XCTAssertFalse(c.hadDot)
    }

    func test_leadingDotIsNotExtension() {
        let c = NameComponents(fullName: ".gitignore")
        XCTAssertEqual(c.base, ".gitignore")
        XCTAssertEqual(c.ext, "")
        XCTAssertFalse(c.hadDot)
    }

    func test_multipleDotsUseLast() {
        let c = NameComponents(fullName: "archive.tar.gz")
        XCTAssertEqual(c.base, "archive.tar")
        XCTAssertEqual(c.ext, "gz")
    }

    func test_recomposeFromParts() {
        XCTAssertEqual(NameComponents(base: "a", ext: "txt", hadDot: true).fullName, "a.txt")
        XCTAssertEqual(NameComponents(base: "a", ext: "", hadDot: false).fullName, "a")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter NameComponentsTests`
Expected: FAIL — `cannot find 'NameComponents' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `RenamerCore/Sources/RenamerCore/NameComponents.swift`:
```swift
import Foundation

/// A filename split into its base and extension parts.
public struct NameComponents: Equatable {
    public let base: String
    public let ext: String
    public let hadDot: Bool

    public init(base: String, ext: String, hadDot: Bool) {
        self.base = base
        self.ext = ext
        self.hadDot = hadDot
    }

    public init(fullName: String) {
        // A leading dot never starts an extension.
        if let dot = fullName.lastIndex(of: "."), dot != fullName.startIndex {
            self.base = String(fullName[fullName.startIndex..<dot])
            self.ext = String(fullName[fullName.index(after: dot)...])
            self.hadDot = true
        } else {
            self.base = fullName
            self.ext = ""
            self.hadDot = false
        }
    }

    public var fullName: String {
        hadDot ? "\(base).\(ext)" : base
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter NameComponentsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/NameComponents.swift RenamerCore/Tests/RenamerCoreTests/NameComponentsTests.swift
git commit -m "feat(core): NameComponents filename splitting"
```

---

## Task 2: FileItem (source file model)

`FileItem` carries everything the engine needs about a file without re-reading disk during evaluation: its URL and modification date. All name parts are derived.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/FileItem.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/FileItemTests.swift`
- Delete: `RenamerCore/Sources/RenamerCore/RenamerCore.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/FileItemTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class FileItemTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }

    func test_derivesNameParts() {
        let i = item("/Users/me/Holiday/IMG_01.jpg")
        XCTAssertEqual(i.fullName, "IMG_01.jpg")
        XCTAssertEqual(i.baseName, "IMG_01")
        XCTAssertEqual(i.ext, "jpg")
        XCTAssertEqual(i.parentName, "Holiday")
        XCTAssertEqual(i.directory, URL(fileURLWithPath: "/Users/me/Holiday"))
    }

    func test_noExtension() {
        let i = item("/tmp/README")
        XCTAssertEqual(i.baseName, "README")
        XCTAssertEqual(i.ext, "")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FileItemTests`
Expected: FAIL — `cannot find 'FileItem' in scope`.

- [ ] **Step 3: Write minimal implementation and delete the placeholder**

Delete the placeholder:
```bash
rm /Users/micz/__DEV__/__renamer/RenamerCore/Sources/RenamerCore/RenamerCore.swift
```

Create `RenamerCore/Sources/RenamerCore/FileItem.swift`:
```swift
import Foundation

/// A file to be renamed. Holds only what the engine needs so evaluation is
/// pure and does not touch disk.
public struct FileItem: Equatable {
    public let url: URL
    public let modificationDate: Date

    public init(url: URL, modificationDate: Date) {
        self.url = url
        self.modificationDate = modificationDate
    }

    public var fullName: String { url.lastPathComponent }
    public var directory: URL { url.deletingLastPathComponent() }
    public var parentName: String { directory.lastPathComponent }

    private var components: NameComponents { NameComponents(fullName: fullName) }
    public var baseName: String { components.base }
    public var ext: String { components.ext }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FileItemTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add -A RenamerCore/Sources/RenamerCore RenamerCore/Tests/RenamerCoreTests/FileItemTests.swift
git commit -m "feat(core): FileItem model"
```

---

## Task 3: Template segments and parser

The parser turns a template string into segments. `{{` and `}}` are literal braces. A token is `{name}` or `{name:argument}`; the argument is the raw text after the first `:`. Unknown token names and unterminated `{` are errors.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/TemplateSegment.swift`
- Create: `RenamerCore/Sources/RenamerCore/TemplateParser.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/TemplateParserTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/TemplateParserTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter TemplateParserTests`
Expected: FAIL — `cannot find 'TemplateParser' in scope`.

- [ ] **Step 3: Write the types**

Create `RenamerCore/Sources/RenamerCore/TemplateSegment.swift`:
```swift
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
```

- [ ] **Step 4: Write the parser**

Create `RenamerCore/Sources/RenamerCore/TemplateParser.swift`:
```swift
import Foundation

public enum TemplateParser {
    public static func parse(_ template: String) throws -> [TemplateSegment] {
        var segments: [TemplateSegment] = []
        var literal = ""
        var chars = Array(template)
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter TemplateParserTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/TemplateSegment.swift RenamerCore/Sources/RenamerCore/TemplateParser.swift RenamerCore/Tests/RenamerCoreTests/TemplateParserTests.swift
git commit -m "feat(core): template parser"
```

---

## Task 4: Fragment (substring extraction)

A fragment argument selects a substring with 1-indexed, possibly-negative positions (negative counts from the end, `-1` is the last character; end is inclusive). Forms: `2-4` (chars 2–4), `3-` (3 to end), `-3-` (last 3 to end), and a bare single number `N` meaning N-to-end (so `-3` = last 3). The separating dash is the first `-` that immediately follows a digit.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/Fragment.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/FragmentTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/FragmentTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FragmentTests`
Expected: FAIL — `cannot find 'Fragment' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/Fragment.swift`:
```swift
import Foundation

/// A 1-indexed, inclusive substring selector. Negative positions count from
/// the end (-1 == last character). `end == nil` means "to the end".
public struct Fragment: Equatable {
    public let start: Int
    public let end: Int?

    public init(start: Int, end: Int?) {
        self.start = start
        self.end = end
    }

    /// Returns nil when `arg` is not a fragment expression (e.g. "upper").
    public static func tryParse(_ arg: String) -> Fragment? {
        let chars = Array(arg)
        guard !chars.isEmpty else { return nil }
        // Find the separating '-': the first '-' that follows a digit.
        var sep: Int? = nil
        for k in 1..<chars.count where chars[k] == "-" && chars[k - 1].isNumber {
            sep = k; break
        }
        if let s = sep {
            let left = String(chars[0..<s])
            let right = String(chars[(s + 1)...])
            guard let start = Int(left) else { return nil }
            if right.isEmpty { return Fragment(start: start, end: nil) }
            guard let end = Int(right) else { return nil }
            return Fragment(start: start, end: end)
        } else {
            guard let single = Int(arg) else { return nil }
            return Fragment(start: single, end: nil)
        }
    }

    public static func parse(_ arg: String) throws -> Fragment {
        guard let f = tryParse(arg) else {
            throw TemplateError.badArgument(token: "fragment", argument: arg)
        }
        return f
    }

    public func apply(to value: String) -> String {
        let chars = Array(value)
        let count = chars.count
        guard count > 0 else { return "" }

        func resolve(_ pos: Int) -> Int {
            // 1-indexed -> 0-indexed; negatives count from end.
            pos > 0 ? pos - 1 : count + pos
        }

        let lo = resolve(start)
        let hi = end.map(resolve) ?? (count - 1)
        let clampedLo = max(0, lo)
        let clampedHi = min(count - 1, hi)
        guard clampedLo <= clampedHi else { return "" }
        return String(chars[clampedLo...clampedHi])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FragmentTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/Fragment.swift RenamerCore/Tests/RenamerCoreTests/FragmentTests.swift
git commit -m "feat(core): substring fragment selector"
```

---

## Task 5: CounterSpec (counter parsing + formatting)

Parses the counter argument and formats a value for a row index. Compact form `001` sets `digits = 3`. Full form is comma-separated `key=value` pairs: `start`, `step`, `digits`, `base` (`d`/`x`/`X`). Value for index `i` is `start + i*step`, zero-padded to `digits` in the chosen base.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/CounterSpec.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/CounterSpecTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/CounterSpecTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter CounterSpecTests`
Expected: FAIL — `cannot find 'CounterSpec' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/CounterSpec.swift`:
```swift
import Foundation

public enum CounterBase: Equatable {
    case decimal, hexLower, hexUpper

    var radix: Int { self == .decimal ? 10 : 16 }
    var uppercase: Bool { self == .hexUpper }
}

public struct CounterSpec: Equatable {
    public var start: Int
    public var step: Int
    public var digits: Int
    public var base: CounterBase

    public init(start: Int = 1, step: Int = 1, digits: Int = 1, base: CounterBase = .decimal) {
        self.start = start
        self.step = step
        self.digits = digits
        self.base = base
    }

    public static func parse(_ arg: String?) throws -> CounterSpec {
        guard let arg, !arg.isEmpty else { return CounterSpec() }

        // Compact form: a run of digits -> digit width.
        if arg.allSatisfy({ $0.isNumber }) {
            return CounterSpec(digits: arg.count)
        }

        var spec = CounterSpec()
        for pair in arg.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else {
                throw TemplateError.badArgument(token: "counter", argument: String(pair))
            }
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "start":
                guard let v = Int(value) else { throw TemplateError.badArgument(token: "counter", argument: value) }
                spec.start = v
            case "step":
                guard let v = Int(value) else { throw TemplateError.badArgument(token: "counter", argument: value) }
                spec.step = v
            case "digits":
                guard let v = Int(value), v >= 0 else { throw TemplateError.badArgument(token: "counter", argument: value) }
                spec.digits = v
            case "base":
                switch value {
                case "d": spec.base = .decimal
                case "x": spec.base = .hexLower
                case "X": spec.base = .hexUpper
                default: throw TemplateError.badArgument(token: "counter", argument: value)
                }
            default:
                throw TemplateError.badArgument(token: "counter", argument: key)
            }
        }
        return spec
    }

    public func format(forIndex index: Int) -> String {
        let value = start + index * step
        let negative = value < 0
        var body = String(abs(value), radix: base.radix, uppercase: base.uppercase)
        if body.count < digits {
            body = String(repeating: "0", count: digits - body.count) + body
        }
        return negative ? "-" + body : body
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter CounterSpecTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/CounterSpec.swift RenamerCore/Tests/RenamerCoreTests/CounterSpecTests.swift
git commit -m "feat(core): counter spec parsing and formatting"
```

---

## Task 6: TemplateEvaluator (segments + file + index → string)

Evaluates segments for one file at one index. String tokens (`name`, `ext`, `parent`) accept a case keyword (`upper`/`lower`/`title`) or a fragment. `counter` uses `CounterSpec`. `date`/`time` format the file's modification date with an ICU pattern (defaults `yyyy-MM-dd` / `HH-mm-ss`). The evaluator takes an explicit `locale` and `timeZone` so date output is deterministic in tests.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/TemplateEvaluator.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/TemplateEvaluatorTests.swift`

Depends on Task 7's `CaseTransformer.apply` for the case keyword. To keep tasks independently testable, this task's case handling is inlined here as a small private helper `caseKeyword(_:)` that returns a `CaseMode`; the actual transform calls `CaseTransformer`. **Task 7 must be implemented before this task's tests pass.** Reorder: implement Task 7 first if executing strictly. (Listed in this order for narrative; the executor of this plan should do Task 7, then Task 6.)

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/TemplateEvaluatorTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class TemplateEvaluatorTests: XCTestCase {
    private let evaluator = TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(identifier: "UTC")!
    )

    private func item(_ path: String, date: Date = Date(timeIntervalSince1970: 0)) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: date)
    }

    private func eval(_ template: String, _ item: FileItem, _ index: Int = 0) throws -> String {
        try evaluator.evaluate(TemplateParser.parse(template), item: item, index: index)
    }

    func test_nameAndExt() throws {
        let i = item("/h/Trip/IMG_01.jpg")
        XCTAssertEqual(try eval("{name}.{ext}", i), "IMG_01.jpg")
    }

    func test_parent() throws {
        XCTAssertEqual(try eval("{parent}_{name}", item("/h/Trip/a.txt")), "Trip_a")
    }

    func test_counter() throws {
        let i = item("/h/a.txt")
        XCTAssertEqual(try eval("img_{counter:001}", i, 4), "img_005")
    }

    func test_caseKeyword() throws {
        XCTAssertEqual(try eval("{name:upper}", item("/h/abc.txt")), "ABC")
    }

    func test_fragment() throws {
        XCTAssertEqual(try eval("{name:1-3}", item("/h/abcdef.txt")), "abc")
    }

    func test_dateUsesModificationDate() throws {
        // 2021-01-02T03:04:05Z
        let d = Date(timeIntervalSince1970: 1_609_556_645)
        XCTAssertEqual(try eval("{date}", item("/h/a.txt", date: d)), "2021-01-02")
        XCTAssertEqual(try eval("{time}", item("/h/a.txt", date: d)), "03-04-05")
        XCTAssertEqual(try eval("{date:yyyyMMdd}", item("/h/a.txt", date: d)), "20210102")
    }

    func test_badFragmentOrKeywordThrows() {
        XCTAssertThrowsError(try eval("{name:nonsense!}", item("/h/a.txt")))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter TemplateEvaluatorTests`
Expected: FAIL — `cannot find 'TemplateEvaluator' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/TemplateEvaluator.swift`:
```swift
import Foundation

public struct TemplateEvaluator {
    private let locale: Locale
    private let timeZone: TimeZone

    public init(locale: Locale = Locale(identifier: "en_US_POSIX"),
                timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    public func evaluate(_ segments: [TemplateSegment], item: FileItem, index: Int) throws -> String {
        var out = ""
        for segment in segments {
            switch segment {
            case .literal(let text):
                out += text
            case .token(let spec):
                out += try value(for: spec, item: item, index: index)
            }
        }
        return out
    }

    private func value(for spec: TokenSpec, item: FileItem, index: Int) throws -> String {
        switch spec.name {
        case .name:   return try stringValue(item.baseName, arg: spec.argument)
        case .ext:    return try stringValue(item.ext, arg: spec.argument)
        case .parent: return try stringValue(item.parentName, arg: spec.argument)
        case .counter:
            return try CounterSpec.parse(spec.argument).format(forIndex: index)
        case .date:
            return formattedDate(item.modificationDate, pattern: spec.argument ?? "yyyy-MM-dd")
        case .time:
            return formattedDate(item.modificationDate, pattern: spec.argument ?? "HH-mm-ss")
        }
    }

    private func stringValue(_ base: String, arg: String?) throws -> String {
        guard let arg, !arg.isEmpty else { return base }
        switch arg {
        case "upper": return CaseTransformer.apply(base, mode: .upper, stripDiacritics: false)
        case "lower": return CaseTransformer.apply(base, mode: .lower, stripDiacritics: false)
        case "title": return CaseTransformer.apply(base, mode: .title, stripDiacritics: false)
        default:
            return try Fragment.parse(arg).apply(to: base)
        }
    }

    private func formattedDate(_ date: Date, pattern: String) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter TemplateEvaluatorTests`
Expected: PASS (requires Task 7 done).

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/TemplateEvaluator.swift RenamerCore/Tests/RenamerCoreTests/TemplateEvaluatorTests.swift
git commit -m "feat(core): template evaluator"
```

---

## Task 7: CaseTransformer

> **Execution order note:** implement this task **before** Task 6 (the evaluator references `CaseTransformer.apply`).

`none` returns the input unchanged (apart from optional diacritics stripping). `title` capitalizes the first letter after every non-alphanumeric boundary. Diacritics stripping uses Unicode diacritic-insensitive folding (note in spec §12: distinct letters like Polish `ł` are not folded by this method — a transliteration table is a future enhancement).

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/CaseTransformer.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/CaseTransformerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/CaseTransformerTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class CaseTransformerTests: XCTestCase {
    func test_none() {
        XCTAssertEqual(CaseTransformer.apply("MixedCase", mode: .none, stripDiacritics: false), "MixedCase")
    }
    func test_lowerUpper() {
        XCTAssertEqual(CaseTransformer.apply("AbC", mode: .lower, stripDiacritics: false), "abc")
        XCTAssertEqual(CaseTransformer.apply("AbC", mode: .upper, stripDiacritics: false), "ABC")
    }
    func test_title() {
        XCTAssertEqual(CaseTransformer.apply("hello world-again", mode: .title, stripDiacritics: false),
                       "Hello World-Again")
    }
    func test_stripDiacritics() {
        XCTAssertEqual(CaseTransformer.apply("café", mode: .none, stripDiacritics: true), "cafe")
        XCTAssertEqual(CaseTransformer.apply("ąź", mode: .none, stripDiacritics: true), "az")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter CaseTransformerTests`
Expected: FAIL — `cannot find 'CaseTransformer' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/CaseTransformer.swift`:
```swift
import Foundation

public enum CaseMode: String, Equatable, CaseIterable {
    case none, lower, upper, title
}

public enum CaseTransformer {
    public static func apply(_ input: String, mode: CaseMode, stripDiacritics: Bool) -> String {
        var s = input
        if stripDiacritics {
            s = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }
        switch mode {
        case .none:  return s
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .title: return titlecased(s)
        }
    }

    private static func titlecased(_ s: String) -> String {
        var result = ""
        var atBoundary = true
        for ch in s {
            if ch.isLetter || ch.isNumber {
                result.append(atBoundary ? Character(ch.uppercased()) : ch)
                atBoundary = false
            } else {
                result.append(ch)
                atBoundary = true
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter CaseTransformerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/CaseTransformer.swift RenamerCore/Tests/RenamerCoreTests/CaseTransformerTests.swift
git commit -m "feat(core): case transformer"
```

---

## Task 8: FindReplace (plain + regex)

Empty `search` returns the input unchanged. Plain mode replaces all occurrences (case-insensitive when `caseSensitive == false`). Regex mode uses `NSRegularExpression`; the replacement template supports `$1`…`$n`, `$0`, and `$$`. A bad regex pattern throws.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/FindReplace.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/FindReplaceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/FindReplaceTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class FindReplaceTests: XCTestCase {
    func test_emptySearchIsNoop() throws {
        let fr = FindReplace(search: "", replacement: "x", isRegex: false, caseSensitive: true)
        XCTAssertEqual(try fr.apply(to: "hello"), "hello")
    }

    func test_plainReplaceAll() throws {
        let fr = FindReplace(search: "a", replacement: "X", isRegex: false, caseSensitive: true)
        XCTAssertEqual(try fr.apply(to: "banana"), "bXnXnX")
    }

    func test_plainCaseInsensitive() throws {
        let fr = FindReplace(search: "img", replacement: "photo", isRegex: false, caseSensitive: false)
        XCTAssertEqual(try fr.apply(to: "IMG_01"), "photo_01")
    }

    func test_regexWithGroup() throws {
        let fr = FindReplace(search: "IMG_(\\d+)", replacement: "photo_$1", isRegex: true, caseSensitive: true)
        XCTAssertEqual(try fr.apply(to: "IMG_2381"), "photo_2381")
    }

    func test_badRegexThrows() {
        let fr = FindReplace(search: "(", replacement: "", isRegex: true, caseSensitive: true)
        XCTAssertThrowsError(try fr.apply(to: "x"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FindReplaceTests`
Expected: FAIL — `cannot find 'FindReplace' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/FindReplace.swift`:
```swift
import Foundation

public enum FindReplaceError: Error, Equatable {
    case invalidRegex(String)
}

public struct FindReplace: Equatable {
    public var search: String
    public var replacement: String
    public var isRegex: Bool
    public var caseSensitive: Bool

    public init(search: String, replacement: String, isRegex: Bool, caseSensitive: Bool) {
        self.search = search
        self.replacement = replacement
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
    }

    public func apply(to input: String) throws -> String {
        guard !search.isEmpty else { return input }

        if isRegex {
            var options: NSRegularExpression.Options = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: search, options: options)
            } catch {
                throw FindReplaceError.invalidRegex(search)
            }
            let range = NSRange(input.startIndex..., in: input)
            return regex.stringByReplacingMatches(in: input, options: [], range: range,
                                                  withTemplate: replacement)
        } else {
            var options: String.CompareOptions = []
            if !caseSensitive { options.insert(.caseInsensitive) }
            return input.replacingOccurrences(of: search, with: replacement, options: options)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FindReplaceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/FindReplace.swift RenamerCore/Tests/RenamerCoreTests/FindReplaceTests.swift
git commit -m "feat(core): find and replace (plain + regex)"
```

---

## Task 9: RenameConfig + PlanBuilder.proposedName (the pipeline)

`RenameConfig` holds all user inputs. The pipeline produces one proposed name: build base (template, or original full name if template empty) → find/replace → split into name+ext and apply case separately → recompose.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/RenameConfig.swift`
- Create: `RenamerCore/Sources/RenamerCore/PlanBuilder.swift` (proposedName only in this task)
- Test: `RenamerCore/Tests/RenamerCoreTests/PipelineTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/PipelineTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class PipelineTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private let builder = PlanBuilder(evaluator: TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!))

    func test_templateThenCounter() throws {
        let cfg = RenameConfig(template: "photo_{counter:001}.{ext}",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        XCTAssertEqual(try builder.proposedName(for: item("/h/IMG.JPG"), index: 0, config: cfg), "photo_001.JPG")
    }

    func test_emptyTemplateUsesOriginalThenFindReplace() throws {
        let cfg = RenameConfig(template: "",
                               find: FindReplace(search: "IMG", replacement: "foto", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        XCTAssertEqual(try builder.proposedName(for: item("/h/IMG_1.jpg"), index: 0, config: cfg), "foto_1.jpg")
    }

    func test_separateCaseForNameAndExt() throws {
        let cfg = RenameConfig(template: "",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .upper, extCase: .lower, stripDiacritics: false)
        XCTAssertEqual(try builder.proposedName(for: item("/h/Report.TXT"), index: 0, config: cfg), "REPORT.txt")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter PipelineTests`
Expected: FAIL — `cannot find 'RenameConfig' in scope`.

- [ ] **Step 3: Write RenameConfig**

Create `RenamerCore/Sources/RenamerCore/RenameConfig.swift`:
```swift
import Foundation

public struct RenameConfig: Equatable {
    public var template: String
    public var find: FindReplace
    public var nameCase: CaseMode
    public var extCase: CaseMode
    public var stripDiacritics: Bool

    public init(template: String, find: FindReplace, nameCase: CaseMode,
                extCase: CaseMode, stripDiacritics: Bool) {
        self.template = template
        self.find = find
        self.nameCase = nameCase
        self.extCase = extCase
        self.stripDiacritics = stripDiacritics
    }
}
```

- [ ] **Step 4: Write PlanBuilder.proposedName**

Create `RenamerCore/Sources/RenamerCore/PlanBuilder.swift`:
```swift
import Foundation

public struct PlanBuilder {
    private let evaluator: TemplateEvaluator

    public init(evaluator: TemplateEvaluator = TemplateEvaluator()) {
        self.evaluator = evaluator
    }

    /// Runs the full pipeline for one file. Throws on template/regex errors.
    public func proposedName(for item: FileItem, index: Int, config: RenameConfig) throws -> String {
        // 1. Base.
        let base: String
        if config.template.isEmpty {
            base = item.fullName
        } else {
            let segments = try TemplateParser.parse(config.template)
            base = try evaluator.evaluate(segments, item: item, index: index)
        }
        // 2. Find/replace.
        let replaced = try config.find.apply(to: base)
        // 3. Case on name + ext separately.
        let comps = NameComponents(fullName: replaced)
        let newBase = CaseTransformer.apply(comps.base, mode: config.nameCase,
                                            stripDiacritics: config.stripDiacritics)
        let newExt = CaseTransformer.apply(comps.ext, mode: config.extCase,
                                           stripDiacritics: config.stripDiacritics)
        return NameComponents(base: newBase, ext: newExt, hadDot: comps.hadDot).fullName
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter PipelineTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/RenameConfig.swift RenamerCore/Sources/RenamerCore/PlanBuilder.swift RenamerCore/Tests/RenamerCoreTests/PipelineTests.swift
git commit -m "feat(core): rename config and proposed-name pipeline"
```

---

## Task 10: RenameRow, FileSystemProbe, CollisionDetector

Annotate proposed names with status: hard error for empty/invalid names (`/` or `:`) and duplicate targets (case-insensitive within the same directory); warning for a target that already exists on disk and is not itself one of the sources being renamed.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/RenameRow.swift`
- Create: `RenamerCore/Sources/RenamerCore/FileSystemProbe.swift`
- Create: `RenamerCore/Sources/RenamerCore/CollisionDetector.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/CollisionDetectorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/CollisionDetectorTests.swift`:
```swift
import XCTest
@testable import RenamerCore

private struct FakeProbe: FileSystemProbe {
    let existing: Set<String>
    func exists(_ url: URL) -> Bool { existing.contains(url.path) }
}

final class CollisionDetectorTests: XCTestCase {
    private func row(_ dir: String, _ original: String, _ proposed: String) -> RenameRow {
        let item = FileItem(url: URL(fileURLWithPath: dir).appendingPathComponent(original),
                            modificationDate: Date(timeIntervalSince1970: 0))
        return RenameRow(item: item, proposedName: proposed, status: .ok, message: nil)
    }

    func test_invalidCharacterIsError() {
        let rows = [row("/h", "a.txt", "a/b.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: []))
        XCTAssertEqual(out[0].status, .error)
    }

    func test_emptyNameIsError() {
        let rows = [row("/h", "a.txt", "")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: []))
        XCTAssertEqual(out[0].status, .error)
    }

    func test_duplicateTargetsAreErrors() {
        let rows = [row("/h", "a.txt", "same.txt"), row("/h", "b.txt", "SAME.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: []))
        XCTAssertEqual(out[0].status, .error)
        XCTAssertEqual(out[1].status, .error)
    }

    func test_existingFileOnDiskIsWarning() {
        let rows = [row("/h", "a.txt", "taken.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: ["/h/taken.txt"]))
        XCTAssertEqual(out[0].status, .warning)
    }

    func test_renamingOntoOwnSourceIsNotWarning() {
        // Source b.txt exists on disk and is also being renamed; a.txt -> b.txt is fine.
        let rows = [row("/h", "a.txt", "b.txt"), row("/h", "b.txt", "c.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: ["/h/a.txt", "/h/b.txt"]))
        XCTAssertEqual(out[0].status, .ok)
        XCTAssertEqual(out[1].status, .ok)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter CollisionDetectorTests`
Expected: FAIL — `cannot find 'RenameRow' in scope`.

- [ ] **Step 3: Write RenameRow and FileSystemProbe**

Create `RenamerCore/Sources/RenamerCore/RenameRow.swift`:
```swift
import Foundation

public enum RowStatus: Equatable {
    case ok, warning, error
}

public struct RenameRow: Equatable {
    public let item: FileItem
    public let proposedName: String
    public var status: RowStatus
    public var message: String?

    public init(item: FileItem, proposedName: String, status: RowStatus, message: String?) {
        self.item = item
        self.proposedName = proposedName
        self.status = status
        self.message = message
    }

    /// Destination URL in the same directory as the source.
    public var targetURL: URL { item.directory.appendingPathComponent(proposedName) }
}
```

Create `RenamerCore/Sources/RenamerCore/FileSystemProbe.swift`:
```swift
import Foundation

public protocol FileSystemProbe {
    func exists(_ url: URL) -> Bool
}

public struct DefaultFileSystemProbe: FileSystemProbe {
    public init() {}
    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
```

- [ ] **Step 4: Write CollisionDetector**

Create `RenamerCore/Sources/RenamerCore/CollisionDetector.swift`:
```swift
import Foundation

public enum CollisionDetector {
    public static func annotate(_ rows: [RenameRow], probe: FileSystemProbe) -> [RenameRow] {
        var out = rows
        let sourcePaths = Set(rows.map { $0.item.url.path.lowercased() })

        // 1. Per-row name validation.
        for i in out.indices {
            let name = out[i].proposedName
            if name.isEmpty || name.contains("/") || name.contains(":") {
                out[i].status = .error
                out[i].message = "Niedozwolona nazwa"
            } else {
                out[i].status = .ok
                out[i].message = nil
            }
        }

        // 2. Duplicate target detection (case-insensitive, per directory).
        var groups: [String: [Int]] = [:]
        for i in out.indices where out[i].status != .error {
            let key = out[i].targetURL.path.lowercased()
            groups[key, default: []].append(i)
        }
        for (_, indices) in groups where indices.count > 1 {
            for i in indices {
                out[i].status = .error
                out[i].message = "Duplikat nazwy"
            }
        }

        // 3. Existing-on-disk warning (skip if the target is one of our sources).
        for i in out.indices where out[i].status == .ok {
            let target = out[i].targetURL
            if probe.exists(target), !sourcePaths.contains(target.path.lowercased()) {
                out[i].status = .warning
                out[i].message = "Plik już istnieje"
            }
        }
        return out
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter CollisionDetectorTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/RenameRow.swift RenamerCore/Sources/RenamerCore/FileSystemProbe.swift RenamerCore/Sources/RenamerCore/CollisionDetector.swift RenamerCore/Tests/RenamerCoreTests/CollisionDetectorTests.swift
git commit -m "feat(core): collision detection and row status"
```

---

## Task 11: PlanBuilder.build (full plan)

Combine the pipeline and collision detector into one call: produce rows for all items in order. A template/regex error marks **every** row as an error with the message; per-file evaluation errors mark only that row.

**Files:**
- Modify: `RenamerCore/Sources/RenamerCore/PlanBuilder.swift` (add `build`)
- Test: `RenamerCore/Tests/RenamerCoreTests/PlanBuilderBuildTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/PlanBuilderBuildTests.swift`:
```swift
import XCTest
@testable import RenamerCore

private struct NoProbe: FileSystemProbe { func exists(_ url: URL) -> Bool { false } }

final class PlanBuilderBuildTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private let builder = PlanBuilder(evaluator: TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!))

    func test_buildsRowsWithCounterByOrder() {
        let cfg = RenameConfig(template: "f_{counter:01}.{ext}",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        let rows = builder.build(items: [item("/h/a.jpg"), item("/h/b.jpg")], config: cfg, probe: NoProbe())
        XCTAssertEqual(rows.map(\.proposedName), ["f_01.jpg", "f_02.jpg"])
        XCTAssertEqual(rows.map(\.status), [.ok, .ok])
    }

    func test_badTemplateMarksAllRowsError() {
        let cfg = RenameConfig(template: "{bogus}",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        let rows = builder.build(items: [item("/h/a.jpg")], config: cfg, probe: NoProbe())
        XCTAssertEqual(rows[0].status, .error)
        XCTAssertNotNil(rows[0].message)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter PlanBuilderBuildTests`
Expected: FAIL — `value of type 'PlanBuilder' has no member 'build'`.

- [ ] **Step 3: Add `build` to PlanBuilder**

Append to `RenamerCore/Sources/RenamerCore/PlanBuilder.swift`, inside the `PlanBuilder` struct (after `proposedName`):
```swift
    /// Builds annotated rows for all items in the given order. Counter indices
    /// follow array order, so callers sort `items` before calling.
    public func build(items: [FileItem], config: RenameConfig, probe: FileSystemProbe) -> [RenameRow] {
        // A template parse error invalidates the whole batch.
        if !config.template.isEmpty {
            do { _ = try TemplateParser.parse(config.template) }
            catch {
                return items.map {
                    RenameRow(item: $0, proposedName: $0.fullName, status: .error,
                              message: "Błędny szablon")
                }
            }
        }

        var rows: [RenameRow] = []
        for (index, item) in items.enumerated() {
            do {
                let name = try proposedName(for: item, index: index, config: config)
                rows.append(RenameRow(item: item, proposedName: name, status: .ok, message: nil))
            } catch {
                rows.append(RenameRow(item: item, proposedName: item.fullName, status: .error,
                                      message: "Błąd wyrażenia"))
            }
        }
        return CollisionDetector.annotate(rows, probe: probe)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter PlanBuilderBuildTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/PlanBuilder.swift RenamerCore/Tests/RenamerCoreTests/PlanBuilderBuildTests.swift
git commit -m "feat(core): full plan builder"
```

---

## Task 12: RenameExecutor + UndoBatch (two-phase, safe)

Execute renames safely using a two-phase approach: move every source to a unique temp name in its directory, then move each temp to its final target. This inherently handles cycles (`a↔b`) and case-only renames on case-insensitive APFS. On a target that already exists and is not a source, move it to Trash first (overwrite). Record every actual move so `UndoBatch` can reverse them.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/RenameExecutor.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/RenameExecutorTests.swift`

- [ ] **Step 1: Write the failing test (uses a real temp directory)**

Create `RenamerCore/Tests/RenamerCoreTests/RenameExecutorTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter RenameExecutorTests`
Expected: FAIL — `cannot find 'Move' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/RenameExecutor.swift`:
```swift
import Foundation

/// One intended rename, or one recorded physical move (reused for both).
public struct Move: Equatable {
    public let from: URL
    public let to: URL
    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
    }
}

public struct MoveFailure: Equatable {
    public let move: Move
    public let message: String
}

/// Records the physical moves performed, in order, so they can be reversed.
public struct UndoBatch {
    public let moves: [Move]
    private let fileManager: FileManager

    public init(moves: [Move], fileManager: FileManager = .default) {
        self.moves = moves
        self.fileManager = fileManager
    }

    /// Reverse every recorded move, last performed first.
    public func undo() throws {
        for move in moves.reversed() {
            try fileManager.moveItem(at: move.to, to: move.from)
        }
    }
}

public struct ExecutionResult {
    public let undo: UndoBatch
    public let failures: [MoveFailure]
}

public struct RenameExecutor {
    private let fileManager: FileManager
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Two-phase rename: sources -> temp, then temp -> final target.
    public func execute(_ moves: [Move], overwrite: Bool) throws -> ExecutionResult {
        var performed: [Move] = []
        var failures: [MoveFailure] = []

        // Phase 1: move each source to a unique temp name in its own directory.
        var temps: [(temp: URL, final: URL)] = []
        for move in moves {
            let temp = move.from.deletingLastPathComponent()
                .appendingPathComponent(".renamer-tmp-" + UUID().uuidString)
            do {
                try fileManager.moveItem(at: move.from, to: temp)
                performed.append(Move(from: move.from, to: temp))
                temps.append((temp: temp, final: move.to))
            } catch {
                failures.append(MoveFailure(move: move, message: error.localizedDescription))
            }
        }

        // Phase 2: move each temp to its final target.
        for entry in temps {
            do {
                if fileManager.fileExists(atPath: entry.final.path) {
                    if overwrite {
                        try fileManager.trashItem(at: entry.final, resultingItemURL: nil)
                    } else {
                        // Cannot place final; leave the file at its temp name and report.
                        failures.append(MoveFailure(
                            move: Move(from: entry.temp, to: entry.final),
                            message: "Cel istnieje"))
                        continue
                    }
                }
                try fileManager.moveItem(at: entry.temp, to: entry.final)
                performed.append(Move(from: entry.temp, to: entry.final))
            } catch {
                failures.append(MoveFailure(
                    move: Move(from: entry.temp, to: entry.final),
                    message: error.localizedDescription))
            }
        }

        return ExecutionResult(undo: UndoBatch(moves: performed, fileManager: fileManager),
                               failures: failures)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter RenameExecutorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/RenameExecutor.swift RenamerCore/Tests/RenamerCoreTests/RenameExecutorTests.swift
git commit -m "feat(core): two-phase rename executor with undo"
```

---

## Task 13: FileItemLoader (read modification date from disk)

A thin disk adapter the app uses to turn URLs into `FileItem`s. Tested against a real temp file.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/FileItemLoader.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/FileItemLoaderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/FileItemLoaderTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class FileItemLoaderTests: XCTestCase {
    func test_loadsNameAndModificationDate() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loader-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)

        let item = try FileItemLoader.load(url)
        XCTAssertEqual(item.fullName, "doc.txt")
        XCTAssertEqual(item.url, url)
        XCTAssertLessThan(abs(item.modificationDate.timeIntervalSinceNow), 60)
    }

    func test_missingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).txt")
        XCTAssertThrowsError(try FileItemLoader.load(url))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FileItemLoaderTests`
Expected: FAIL — `cannot find 'FileItemLoader' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/FileItemLoader.swift`:
```swift
import Foundation

public enum FileItemLoader {
    public static func load(_ url: URL) throws -> FileItem {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        let date = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        return FileItem(url: url, modificationDate: date)
    }

    public static func load(_ urls: [URL]) -> [FileItem] {
        urls.compactMap { try? load($0) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter FileItemLoaderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/FileItemLoader.swift RenamerCore/Tests/RenamerCoreTests/FileItemLoaderTests.swift
git commit -m "feat(core): file item loader"
```

---

## Task 14: RenameEngine façade + full suite green

A small façade the app calls: build a plan, and execute the rows that are not errors. This is the single public entry point the UI needs.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/RenameEngine.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/RenameEngineTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/RenameEngineTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter RenameEngineTests`
Expected: FAIL — `cannot find 'RenameEngine' in scope`.

- [ ] **Step 3: Write the implementation**

Create `RenamerCore/Sources/RenamerCore/RenameEngine.swift`:
```swift
import Foundation

/// Public entry point for the UI: build a plan, then apply non-error rows.
public struct RenameEngine {
    private let builder: PlanBuilder
    private let probe: FileSystemProbe
    private let executor: RenameExecutor

    public init(builder: PlanBuilder = PlanBuilder(),
                probe: FileSystemProbe = DefaultFileSystemProbe(),
                executor: RenameExecutor = RenameExecutor()) {
        self.builder = builder
        self.probe = probe
        self.executor = executor
    }

    public func plan(items: [FileItem], config: RenameConfig) -> [RenameRow] {
        builder.build(items: items, config: config, probe: probe)
    }

    /// Applies every row that is not an error (rows that only differ by a
    /// no-op name are skipped). Returns the execution result with undo data.
    public func apply(rows: [RenameRow], overwrite: Bool) throws -> ExecutionResult {
        let moves = rows
            .filter { $0.status != .error && $0.proposedName != $0.item.fullName }
            .map { Move(from: $0.item.url, to: $0.targetURL) }
        return try executor.execute(moves, overwrite: overwrite)
    }
}
```

- [ ] **Step 4: Run the full test suite**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test`
Expected: PASS — all tests across every file, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/RenameEngine.swift RenamerCore/Tests/RenamerCoreTests/RenameEngineTests.swift
git commit -m "feat(core): RenameEngine façade"
```

---

## Done — what Plan 2 will build on

After this plan, `RenamerCore` is a complete, tested engine with this public surface the app will use:
- `FileItemLoader.load([URL]) -> [FileItem]`
- `RenameConfig`, `FindReplace`, `CaseMode`
- `RenameEngine.plan(items:config:) -> [RenameRow]` (drives the live preview)
- `RenameRow` (`proposedName`, `status`, `message`, `targetURL`)
- `RenameEngine.apply(rows:overwrite:) -> ExecutionResult` (returns `UndoBatch`)
- `ExecutionResult.undo.undo()` (the "Cofnij ostatnią" button)

**Plan 2 (separate plan)** will cover: the Xcode app project, the SwiftUI window (token-pill template field, find/replace, case pickers, live preview table), drag-and-drop, the Finder Sync extension + App Group handoff, `UserDefaults` persistence, Developer ID signing, notarization, and DMG packaging.

---

## Self-Review

**Spec coverage (spec §5–§8):**
- §5.1 pipeline order → Task 9. §5.2 tokens → Tasks 3,4,6. §5.3 counter → Task 5. §5.4 dates → Task 6. §5.5 regex → Task 8. §5.6 case → Task 7. §7 preview/collision → Tasks 10,11. §8.1 execution (cycles, case-only, overwrite, partial failure) → Task 12. §8.2 undo → Task 12. UI (§6), Finder integration (§4.3/4.4), persistence (§9), distribution (§10) → deferred to Plan 2 (explicitly scoped out above).
- Gap check: `{name:upper}` combined-with-fragment is out of v1 per spec §5.2 — single argument only, matched by Task 6 (`stringValue` tries keyword then fragment, not both). Consistent.

**Placeholder scan:** No TBD/TODO; every code step has complete code and exact commands/expected output.

**Type consistency:** `Move` used by both executor and `UndoBatch` (Task 12). `RenameRow.targetURL`, `.status`, `.proposedName` consistent across Tasks 10,11,14. `PlanBuilder.build(items:config:probe:)` and `proposedName(for:index:config:)` signatures match Tasks 9,11,14. `CaseTransformer.apply(_:mode:stripDiacritics:)` consistent in Tasks 6,7,9. `TemplateEvaluator(locale:timeZone:)` consistent in Tasks 6,9,11. `FindReplace` initializer consistent across all tests.

**Execution-order caveat:** Task 7 (CaseTransformer) must be implemented before Task 6 (TemplateEvaluator) compiles — flagged in both tasks.
