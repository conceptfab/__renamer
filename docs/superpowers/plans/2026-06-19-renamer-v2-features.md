# Renamer v2 Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four features to the existing Renamer app — post-operation success/failure confirmation, lock-file-extension (default on), user presets (add/delete/rename), and Search/Replace helpers (regex insert menu + variable insert menu in the Replace field).

**Architecture:** Pure engine logic lands in `RenamerCore` and is driven with TDD (`swift test`): the lock-extension pipeline branch, per-file token expansion in the Replace field, `Codable` on the config types, and a `Preset` value + pure `PresetManager`. The SwiftUI app (`Renamer/`, an SPM executable with no test harness) wires this in via the existing `RenameSession: ObservableObject`; those tasks use `swift build` plus explicit manual verification with `swift run Renamer`.

**Tech Stack:** Swift 5.9+, SwiftPM, XCTest, SwiftUI, Foundation (`NSRegularExpression`, `JSONEncoder`/`JSONDecoder`, `UserDefaults`). macOS 13+.

**Reference spec:** `docs/superpowers/specs/2026-06-19-renamer-v2-features-design.md`.

**Precondition:** This builds on the implemented MVP. Assumes a git repo exists (the MVP plan ran `git init`). If `git status` fails in the steps below, run `git init` once first.

---

## File Structure

```
RenamerCore/Sources/RenamerCore/
  RenameConfig.swift        # MODIFY: add lockExtension + Codable
  FindReplace.swift         # MODIFY: add Codable
  CaseTransformer.swift     # MODIFY: CaseMode: Codable
  PlanBuilder.swift         # MODIFY: lock-extension branch + replace-token expansion
  Preset.swift              # CREATE: Preset value (id, name, config)
  PresetManager.swift       # CREATE: pure add/delete/rename
RenamerCore/Tests/RenamerCoreTests/
  LockExtensionTests.swift  # CREATE
  ReplaceTokensTests.swift  # CREATE
  ConfigCodableTests.swift  # CREATE
  PresetManagerTests.swift  # CREATE

Renamer/Sources/Renamer/
  SettingsStore.swift       # MODIFY: persist lockExtension
  RenameSession.swift       # MODIFY: lockExtension, presets, banner/failure state, insert methods
  ControlsPanel.swift       # MODIFY: mode picker, lock toggle, helpers, presets bar
  ContentView.swift         # MODIFY: success banner overlay + failure sheet
  PresetStore.swift         # CREATE: [Preset] <-> UserDefaults JSON
  VariableInsertMenu.swift  # CREATE: reusable insert menu (name + replace fields)
  RegexHelperMenu.swift     # CREATE: regex snippet insert menu for Search
  ResultBanner.swift        # CREATE: success banner view
  FailureReportSheet.swift  # CREATE: failure list sheet
```

Phase A (Tasks 1–4) = `RenamerCore`, TDD. Phase B (Tasks 5–11) = app, build + manual verification.

---

# Phase A — RenamerCore (TDD)

## Task 1: Lock-extension pipeline branch

Add `lockExtension` to `RenameConfig` (default `false` to keep all existing call sites/tests compiling) and branch the pipeline: when on, strip the original extension, process only the name, then reattach the original extension verbatim.

**Files:**
- Modify: `RenamerCore/Sources/RenamerCore/RenameConfig.swift`
- Modify: `RenamerCore/Sources/RenamerCore/PlanBuilder.swift:11-29`
- Test: `RenamerCore/Tests/RenamerCoreTests/LockExtensionTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/LockExtensionTests.swift`:
```swift
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
        // Template has no .{ext}; lock should append original ".jpg".
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
        // Replace "jpg" -> "txt"; with lock, extension is protected.
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter LockExtensionTests`
Expected: FAIL — `extra argument 'lockExtension' in call`.

- [ ] **Step 3: Add `lockExtension` to RenameConfig**

Replace the body of `RenamerCore/Sources/RenamerCore/RenameConfig.swift` with:
```swift
import Foundation

public struct RenameConfig: Equatable {
    public var template: String
    public var find: FindReplace
    public var nameCase: CaseMode
    public var extCase: CaseMode
    public var stripDiacritics: Bool
    public var lockExtension: Bool

    public init(template: String, find: FindReplace, nameCase: CaseMode,
                extCase: CaseMode, stripDiacritics: Bool, lockExtension: Bool = false) {
        self.template = template
        self.find = find
        self.nameCase = nameCase
        self.extCase = extCase
        self.stripDiacritics = stripDiacritics
        self.lockExtension = lockExtension
    }
}
```

- [ ] **Step 4: Branch the pipeline in PlanBuilder**

Replace `proposedName` (lines 11-29) in `RenamerCore/Sources/RenamerCore/PlanBuilder.swift` with:
```swift
    /// Runs the full pipeline for one file. Throws on template/regex errors.
    public func proposedName(for item: FileItem, index: Int, config: RenameConfig) throws -> String {
        // 1. Base. When locked, work on the name part only.
        let base: String
        if config.template.isEmpty {
            base = config.lockExtension ? item.baseName : item.fullName
        } else {
            let segments = try TemplateParser.parse(config.template)
            let evaluated = try evaluator.evaluate(segments, item: item, index: index)
            base = config.lockExtension ? NameComponents(fullName: evaluated).base : evaluated
        }
        // 2. Find/replace.
        let replaced = try config.find.apply(to: base)
        // 3. Case + recompose.
        if config.lockExtension {
            let original = NameComponents(fullName: item.fullName)
            let newBase = CaseTransformer.apply(replaced, mode: config.nameCase,
                                                stripDiacritics: config.stripDiacritics)
            return NameComponents(base: newBase, ext: original.ext, hadDot: original.hadDot).fullName
        } else {
            let comps = NameComponents(fullName: replaced)
            let newBase = CaseTransformer.apply(comps.base, mode: config.nameCase,
                                                stripDiacritics: config.stripDiacritics)
            let newExt = CaseTransformer.apply(comps.ext, mode: config.extCase,
                                               stripDiacritics: config.stripDiacritics)
            return NameComponents(base: newBase, ext: newExt, hadDot: comps.hadDot).fullName
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass (and nothing regressed)**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test`
Expected: PASS — all tests including `LockExtensionTests` and the existing `PipelineTests`.

- [ ] **Step 6: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/RenameConfig.swift RenamerCore/Sources/RenamerCore/PlanBuilder.swift RenamerCore/Tests/RenamerCoreTests/LockExtensionTests.swift
git commit -m "feat(core): lock file extension in rename pipeline"
```

---

## Task 2: Per-file token expansion in the Replace field

The Replace string becomes a mini-template expanded per file before the find/replace runs, so `{counter}`, `{date}` etc. work in Replace. `$1` (regex group) passes through untouched.

**Files:**
- Modify: `RenamerCore/Sources/RenamerCore/PlanBuilder.swift` (the `// 2. Find/replace.` step)
- Test: `RenamerCore/Tests/RenamerCoreTests/ReplaceTokensTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/ReplaceTokensTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class ReplaceTokensTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private let builder = PlanBuilder(evaluator: TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!))

    func test_counterTokenInReplacementExpandsPerIndex() throws {
        // Replace "x" with "{counter:01}" — counter follows the row index.
        let cfg = RenameConfig(
            template: "",
            find: FindReplace(search: "x", replacement: "{counter:01}", isRegex: false, caseSensitive: true),
            nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true)
        XCTAssertEqual(try builder.proposedName(for: item("/h/x.txt"), index: 0, config: cfg), "01.txt")
        XCTAssertEqual(try builder.proposedName(for: item("/h/x.txt"), index: 4, config: cfg), "05.txt")
    }

    func test_regexGroupAndTokenCoexist() throws {
        let cfg = RenameConfig(
            template: "",
            find: FindReplace(search: "IMG_(\\d+)", replacement: "{counter:001}_$1",
                              isRegex: true, caseSensitive: true),
            nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true)
        XCTAssertEqual(try builder.proposedName(for: item("/h/IMG_42.jpg"), index: 0, config: cfg),
                       "001_42.jpg")
    }

    func test_emptyReplacementUnaffected() throws {
        let cfg = RenameConfig(
            template: "",
            find: FindReplace(search: "_old", replacement: "", isRegex: false, caseSensitive: true),
            nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true)
        XCTAssertEqual(try builder.proposedName(for: item("/h/a_old.txt"), index: 0, config: cfg), "a.txt")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter ReplaceTokensTests`
Expected: FAIL — `test_counterTokenInReplacementExpandsPerIndex` produces `{counter:01}.txt` (literal), not `01.txt`.

- [ ] **Step 3: Expand the replacement before applying**

In `RenamerCore/Sources/RenamerCore/PlanBuilder.swift`, replace the find/replace step:
```swift
        // 2. Find/replace.
        let replaced = try config.find.apply(to: base)
```
with:
```swift
        // 2. Find/replace. The replacement is a mini-template expanded per file
        //    so tokens like {counter} work; regex backrefs ($1) pass through.
        let expandedReplacement = try evaluator.evaluate(
            TemplateParser.parse(config.find.replacement), item: item, index: index)
        let effectiveFind = FindReplace(search: config.find.search,
                                        replacement: expandedReplacement,
                                        isRegex: config.find.isRegex,
                                        caseSensitive: config.find.caseSensitive)
        let replaced = try effectiveFind.apply(to: base)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/PlanBuilder.swift RenamerCore/Tests/RenamerCoreTests/ReplaceTokensTests.swift
git commit -m "feat(core): expand variable tokens in replacement per file"
```

---

## Task 3: Codable on config types

Make `CaseMode`, `FindReplace`, and `RenameConfig` `Codable` so presets can be serialized.

**Files:**
- Modify: `RenamerCore/Sources/RenamerCore/CaseTransformer.swift:3`
- Modify: `RenamerCore/Sources/RenamerCore/FindReplace.swift:7`
- Modify: `RenamerCore/Sources/RenamerCore/RenameConfig.swift:3`
- Test: `RenamerCore/Tests/RenamerCoreTests/ConfigCodableTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/ConfigCodableTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class ConfigCodableTests: XCTestCase {
    func test_renameConfigRoundTrips() throws {
        let cfg = RenameConfig(
            template: "photo_{counter:001}",
            find: FindReplace(search: "IMG", replacement: "foto", isRegex: true, caseSensitive: false),
            nameCase: .upper, extCase: .lower, stripDiacritics: true, lockExtension: true)
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(RenameConfig.self, from: data)
        XCTAssertEqual(decoded, cfg)
    }

    func test_caseModeRoundTrips() throws {
        for mode in CaseMode.allCases {
            let data = try JSONEncoder().encode(mode)
            XCTAssertEqual(try JSONDecoder().decode(CaseMode.self, from: data), mode)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter ConfigCodableTests`
Expected: FAIL — `instance method 'encode' requires that 'RenameConfig' conform to 'Encodable'`.

- [ ] **Step 3: Add conformances**

In `RenamerCore/Sources/RenamerCore/CaseTransformer.swift`, change line 3:
```swift
public enum CaseMode: String, Equatable, CaseIterable {
```
to:
```swift
public enum CaseMode: String, Equatable, CaseIterable, Codable {
```

In `RenamerCore/Sources/RenamerCore/FindReplace.swift`, change line 7:
```swift
public struct FindReplace: Equatable {
```
to:
```swift
public struct FindReplace: Equatable, Codable {
```

In `RenamerCore/Sources/RenamerCore/RenameConfig.swift`, change line 3:
```swift
public struct RenameConfig: Equatable {
```
to:
```swift
public struct RenameConfig: Equatable, Codable {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/CaseTransformer.swift RenamerCore/Sources/RenamerCore/FindReplace.swift RenamerCore/Sources/RenamerCore/RenameConfig.swift RenamerCore/Tests/RenamerCoreTests/ConfigCodableTests.swift
git commit -m "feat(core): make config types Codable"
```

---

## Task 4: Preset value + PresetManager

A `Preset` is a named config. `PresetManager` provides pure add/delete/rename over `[Preset]`.

**Files:**
- Create: `RenamerCore/Sources/RenamerCore/Preset.swift`
- Create: `RenamerCore/Sources/RenamerCore/PresetManager.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/PresetManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `RenamerCore/Tests/RenamerCoreTests/PresetManagerTests.swift`:
```swift
import XCTest
@testable import RenamerCore

final class PresetManagerTests: XCTestCase {
    private func preset(_ id: String, _ name: String) -> Preset {
        Preset(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(id)")!,
               name: name,
               config: RenameConfig(template: "",
                                    find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                                    nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true))
    }

    func test_add() {
        let result = PresetManager.add(preset("01", "A"), to: [])
        XCTAssertEqual(result.map(\.name), ["A"])
    }

    func test_delete() {
        let a = preset("01", "A"); let b = preset("02", "B")
        let result = PresetManager.delete(id: a.id, from: [a, b])
        XCTAssertEqual(result.map(\.name), ["B"])
    }

    func test_deleteUnknownIdLeavesListUnchanged() {
        let a = preset("01", "A")
        let result = PresetManager.delete(id: preset("99", "X").id, from: [a])
        XCTAssertEqual(result.map(\.name), ["A"])
    }

    func test_rename() {
        let a = preset("01", "A")
        let result = PresetManager.rename(id: a.id, to: "Renamed", in: [a])
        XCTAssertEqual(result.map(\.name), ["Renamed"])
    }

    func test_renameUnknownIdLeavesListUnchanged() {
        let a = preset("01", "A")
        let result = PresetManager.rename(id: preset("99", "X").id, to: "Z", in: [a])
        XCTAssertEqual(result.map(\.name), ["A"])
    }

    func test_presetRoundTrips() throws {
        let a = preset("01", "A")
        let data = try JSONEncoder().encode([a])
        XCTAssertEqual(try JSONDecoder().decode([Preset].self, from: data), [a])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test --filter PresetManagerTests`
Expected: FAIL — `cannot find 'Preset' in scope`.

- [ ] **Step 3: Create Preset**

Create `RenamerCore/Sources/RenamerCore/Preset.swift`:
```swift
import Foundation

/// A named, saved rename configuration.
public struct Preset: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var config: RenameConfig

    public init(id: UUID = UUID(), name: String, config: RenameConfig) {
        self.id = id
        self.name = name
        self.config = config
    }
}
```

- [ ] **Step 4: Create PresetManager**

Create `RenamerCore/Sources/RenamerCore/PresetManager.swift`:
```swift
import Foundation

/// Pure operations over a preset list. Each returns a new array.
public enum PresetManager {
    public static func add(_ preset: Preset, to presets: [Preset]) -> [Preset] {
        presets + [preset]
    }

    public static func delete(id: UUID, from presets: [Preset]) -> [Preset] {
        presets.filter { $0.id != id }
    }

    public static func rename(id: UUID, to name: String, in presets: [Preset]) -> [Preset] {
        presets.map { preset in
            guard preset.id == id else { return preset }
            var copy = preset
            copy.name = name
            return copy
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test`
Expected: PASS — all tests.

- [ ] **Step 6: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add RenamerCore/Sources/RenamerCore/Preset.swift RenamerCore/Sources/RenamerCore/PresetManager.swift RenamerCore/Tests/RenamerCoreTests/PresetManagerTests.swift
git commit -m "feat(core): Preset value and PresetManager operations"
```

---

# Phase B — App (build + manual verification)

> The `Renamer` target is an SPM executable with no test harness, so these tasks verify with `swift build` and explicit manual checks via `swift run Renamer`. Keep app code thin — all branching logic already lives in (and is tested in) `RenamerCore`.

## Task 5: Persist & wire `lockExtension`

**Files:**
- Modify: `Renamer/Sources/Renamer/SettingsStore.swift`
- Modify: `Renamer/Sources/Renamer/RenameSession.swift`

- [ ] **Step 1: Add lockExtension to SettingsStore**

In `Renamer/Sources/Renamer/SettingsStore.swift`:

Add to `Snapshot` (after `stripDiacritics`):
```swift
        var lockExtension: Bool = true
```
Add to `Key`:
```swift
        static let lockExtension = "renamer.lockExtension"
```
In `load()`, add to the `Snapshot(...)` call (after `stripDiacritics:`):
```swift
            lockExtension: defaults.object(forKey: Key.lockExtension) as? Bool ?? true
```
In `save(_:)`, add:
```swift
        defaults.set(snapshot.lockExtension, forKey: Key.lockExtension)
```

- [ ] **Step 2: Wire into RenameSession**

In `Renamer/Sources/Renamer/RenameSession.swift`:

Add the published property after `stripDiacritics` (line 28):
```swift
    @Published var lockExtension: Bool = true
```
In `loadSettings()` add after `stripDiacritics = s.stripDiacritics`:
```swift
        lockExtension = s.lockExtension
```
In `persistSettings()` add `lockExtension: lockExtension` to the `Snapshot(...)`:
```swift
        settings.save(SettingsStore.Snapshot(
            template: template,
            search: search,
            replacement: replacement,
            isRegex: isRegex,
            caseSensitive: caseSensitive,
            nameCase: nameCase,
            extCase: extCase,
            stripDiacritics: stripDiacritics,
            lockExtension: lockExtension
        ))
```
In `rebuildPlanNow()` add `lockExtension: lockExtension` to the `RenameConfig(...)`:
```swift
        let config = RenameConfig(
            template: template,
            find: FindReplace(search: search, replacement: replacement, isRegex: isRegex, caseSensitive: caseSensitive),
            nameCase: nameCase,
            extCase: extCase,
            stripDiacritics: stripDiacritics,
            lockExtension: lockExtension
        )
```

- [ ] **Step 3: Build**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add Renamer/Sources/Renamer/SettingsStore.swift Renamer/Sources/Renamer/RenameSession.swift
git commit -m "feat(app): persist and wire lockExtension"
```

---

## Task 6: Search-mode picker + lock toggle in ControlsPanel

Replace the "Wyrażenie regularne" checkbox with a 2-state segmented picker (Zwykły tekst / Regex), and add the "Chroń rozszerzenie pliku" toggle that disables the extension case picker when on.

**Files:**
- Modify: `Renamer/Sources/Renamer/ControlsPanel.swift:36-67`

- [ ] **Step 1: Replace the toggles row and the case row**

In `Renamer/Sources/Renamer/ControlsPanel.swift`, replace the toggles `HStack` (lines 36-43):
```swift
            HStack(spacing: 16) {
                Toggle("Wyrażenie regularne", isOn: $session.isRegex)
                    .onChange(of: session.isRegex) { _ in session.onConfigChanged() }
                Toggle("Rozróżniaj wielkość", isOn: $session.caseSensitive)
                    .onChange(of: session.caseSensitive) { _ in session.onConfigChanged() }
                Toggle("Usuń diakrytyki", isOn: $session.stripDiacritics)
                    .onChange(of: session.stripDiacritics) { _ in session.onConfigChanged() }
            }
```
with:
```swift
            HStack(spacing: 16) {
                Picker("Tryb", selection: $session.isRegex) {
                    Text("Zwykły tekst").tag(false)
                    Text("Regex").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: session.isRegex) { _ in session.onConfigChanged() }
                Toggle("Rozróżniaj wielkość", isOn: $session.caseSensitive)
                    .onChange(of: session.caseSensitive) { _ in session.onConfigChanged() }
                Toggle("Usuń diakrytyki", isOn: $session.stripDiacritics)
                    .onChange(of: session.stripDiacritics) { _ in session.onConfigChanged() }
                Toggle("Chroń rozszerzenie pliku", isOn: $session.lockExtension)
                    .onChange(of: session.lockExtension) { _ in session.onConfigChanged() }
            }
```

In the same file, in the case `HStack` (lines 57-66), disable the extension picker when locked. Replace:
```swift
                Text("Rozszerzenie")
                    .foregroundStyle(.secondary)
                Picker("Rozszerzenie", selection: $session.extCase) {
                    ForEach(CaseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: session.extCase) { _ in session.onConfigChanged() }
```
with:
```swift
                Text("Rozszerzenie")
                    .foregroundStyle(session.lockExtension ? .tertiary : .secondary)
                Picker("Rozszerzenie", selection: $session.extCase) {
                    ForEach(CaseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .disabled(session.lockExtension)
                .onChange(of: session.extCase) { _ in session.onConfigChanged() }
```

- [ ] **Step 2: Build**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift build`
Expected: `Build complete!`.

- [ ] **Step 3: Manual verification**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift run Renamer`
Then:
1. Drag in a file `Report.JPG`. The "Chroń rozszerzenie pliku" toggle should be ON by default, and the "Rozszerzenie" case picker should be greyed out/disabled.
2. Set "Nazwa" case = `WIELKIE LITERY`. Preview shows `REPORT.JPG` (extension `.JPG` unchanged because locked).
3. Turn the lock OFF. The "Rozszerzenie" picker becomes enabled. Set it to `małe litery`. Preview shows `REPORT.jpg`.
4. The mode control shows a segmented "Zwykły tekst / Regex"; toggling it updates the preview.

- [ ] **Step 4: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add Renamer/Sources/Renamer/ControlsPanel.swift
git commit -m "feat(app): search-mode picker and lock-extension toggle"
```

---

## Task 7: Variable insert menu in Replace + regex helper in Search

Generalize the insert menu into a reusable `VariableInsertMenu`, add it to the Replace field (with regex group items when in regex mode), and add a `RegexHelperMenu` to the Search field plus a one-line cheat sheet.

**Files:**
- Create: `Renamer/Sources/Renamer/VariableInsertMenu.swift`
- Create: `Renamer/Sources/Renamer/RegexHelperMenu.swift`
- Modify: `Renamer/Sources/Renamer/RenameSession.swift` (add insert methods)
- Modify: `Renamer/Sources/Renamer/ControlsPanel.swift` (use new menus; remove old `TokenInsertMenu`)

- [ ] **Step 1: Add insert methods to RenameSession**

In `Renamer/Sources/Renamer/RenameSession.swift`, replace the existing `insertToken` (lines 116-119):
```swift
    func insertToken(_ token: String) {
        template += token
        onConfigChanged()
    }
```
with:
```swift
    func insertToken(_ token: String) {
        template += token
        onConfigChanged()
    }

    func insertReplacementToken(_ token: String) {
        replacement += token
        onConfigChanged()
    }

    func insertSearchToken(_ token: String) {
        search += token
        onConfigChanged()
    }
```

- [ ] **Step 2: Create the reusable variable insert menu**

Create `Renamer/Sources/Renamer/VariableInsertMenu.swift`:
```swift
import SwiftUI

/// A "+ Wstaw" menu that inserts variable tokens via the given closure.
/// When `includeGroups` is true, regex group backrefs are also offered.
struct VariableInsertMenu: View {
    var includeGroups: Bool = false
    let onInsert: (String) -> Void

    var body: some View {
        Menu {
            Button("{name}") { onInsert("{name}") }
            Button("{ext}") { onInsert("{ext}") }
            Button("{parent}") { onInsert("{parent}") }
            Button("{counter:001}") { onInsert("{counter:001}") }
            Button("{date}") { onInsert("{date}") }
            Button("{time}") { onInsert("{time}") }
            if includeGroups {
                Divider()
                Button("$1 (grupa 1)") { onInsert("$1") }
                Button("$2 (grupa 2)") { onInsert("$2") }
                Button("$3 (grupa 3)") { onInsert("$3") }
            }
        } label: {
            Label("Wstaw", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
```

- [ ] **Step 3: Create the regex helper menu**

Create `Renamer/Sources/Renamer/RegexHelperMenu.swift`:
```swift
import SwiftUI

/// A "Wstaw wyrażenie" menu that inserts common regex snippets via the closure.
struct RegexHelperMenu: View {
    let onInsert: (String) -> Void

    var body: some View {
        Menu {
            Button(". — dowolny znak") { onInsert(".") }
            Button(".* — dowolny ciąg") { onInsert(".*") }
            Button("\\d — cyfra") { onInsert("\\d") }
            Button("\\w — znak słowa") { onInsert("\\w") }
            Button("\\s — odstęp") { onInsert("\\s") }
            Button("(…) — grupa") { onInsert("()") }
            Button("[…] — zbiór znaków") { onInsert("[]") }
            Button("^ — początek") { onInsert("^") }
            Button("$ — koniec") { onInsert("$") }
        } label: {
            Label("Wyrażenie", systemImage: "function")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
```

- [ ] **Step 4: Wire the menus into ControlsPanel and remove TokenInsertMenu**

In `Renamer/Sources/Renamer/ControlsPanel.swift`:

Replace `TokenInsertMenu()` (line 17) with:
```swift
                VariableInsertMenu { session.insertToken($0) }
```

Replace the Szukaj/Zamień `HStack` (lines 20-34) with:
```swift
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Szukaj")
                        .frame(width: 90, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("", text: $session.search)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: session.search) { _ in session.onConfigChanged() }
                    if session.isRegex {
                        RegexHelperMenu { session.insertSearchToken($0) }
                    }
                    Text("Zamień")
                        .foregroundStyle(.secondary)
                    TextField("", text: $session.replacement)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: session.replacement) { _ in session.onConfigChanged() }
                    VariableInsertMenu(includeGroups: session.isRegex) { session.insertReplacementToken($0) }
                }
                if session.isRegex {
                    Text(". dowolny znak · .* dowolny ciąg · \\d cyfra · (…) grupa · ^ początek · $ koniec")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 98)
                }
            }
```

Delete the now-unused `TokenInsertMenu` struct (lines 74-91 in the original file).

- [ ] **Step 5: Build**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift build`
Expected: `Build complete!`.

- [ ] **Step 6: Manual verification**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift run Renamer`
Then:
1. Drag in two files `x1.txt`, `x2.txt`. In Replace, click "Wstaw" → "{counter:001}". The Replace field shows `{counter:001}`; preview shows `001.txt`, `002.txt` (counter expands per file). (Search is empty here, so set Search to `x` first to see replacement applied.)
2. Switch mode to "Regex". A "Wyrażenie" menu appears next to Search and a cheat-sheet line shows below; the Replace "Wstaw" menu now also lists `$1`, `$2`, `$3`.
3. Click Search "Wyrażenie" → ".* dowolny ciąg"; `.*` is appended to the Search field.

- [ ] **Step 7: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add Renamer/Sources/Renamer/VariableInsertMenu.swift Renamer/Sources/Renamer/RegexHelperMenu.swift Renamer/Sources/Renamer/RenameSession.swift Renamer/Sources/Renamer/ControlsPanel.swift
git commit -m "feat(app): variable insert in Replace and regex helper in Search"
```

---

## Task 8: PresetStore + RenameSession preset wiring

**Files:**
- Create: `Renamer/Sources/Renamer/PresetStore.swift`
- Modify: `Renamer/Sources/Renamer/RenameSession.swift`

- [ ] **Step 1: Create PresetStore**

Create `Renamer/Sources/Renamer/PresetStore.swift`:
```swift
import Foundation
import RenamerCore

/// Persists the user's presets as JSON in UserDefaults.
struct PresetStore {
    private let defaults = UserDefaults.standard
    private let key = "renamer.presets"

    func load() -> [Preset] {
        guard let data = defaults.data(forKey: key),
              let presets = try? JSONDecoder().decode([Preset].self, from: data) else {
            return []
        }
        return presets
    }

    func save(_ presets: [Preset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}
```

- [ ] **Step 2: Wire presets into RenameSession**

In `Renamer/Sources/Renamer/RenameSession.swift`:

Add published properties after `lockExtension` (added in Task 5):
```swift
    @Published var presets: [Preset] = []
    @Published var selectedPresetID: UUID?
```

Add the store after `private let settings = SettingsStore()` (line 38):
```swift
    private let presetStore = PresetStore()
```

In `init()`, after `loadSettings()`:
```swift
        presets = presetStore.load()
```

Add this group of methods after `insertSearchToken` (added in Task 7):
```swift
    var currentConfig: RenameConfig {
        RenameConfig(
            template: template,
            find: FindReplace(search: search, replacement: replacement, isRegex: isRegex, caseSensitive: caseSensitive),
            nameCase: nameCase, extCase: extCase, stripDiacritics: stripDiacritics, lockExtension: lockExtension)
    }

    func loadConfig(_ config: RenameConfig) {
        template = config.template
        search = config.find.search
        replacement = config.find.replacement
        isRegex = config.find.isRegex
        caseSensitive = config.find.caseSensitive
        nameCase = config.nameCase
        extCase = config.extCase
        stripDiacritics = config.stripDiacritics
        lockExtension = config.lockExtension
        onConfigChanged()
    }

    func applyPreset(_ preset: Preset) {
        loadConfig(preset.config)
        selectedPresetID = preset.id
    }

    func saveCurrentAsPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = Preset(name: trimmed, config: currentConfig)
        presets = PresetManager.add(preset, to: presets)
        presetStore.save(presets)
        selectedPresetID = preset.id
    }

    func deletePreset(id: UUID) {
        presets = PresetManager.delete(id: id, from: presets)
        presetStore.save(presets)
        if selectedPresetID == id { selectedPresetID = nil }
    }

    func renamePreset(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets = PresetManager.rename(id: id, to: trimmed, in: presets)
        presetStore.save(presets)
    }
```

- [ ] **Step 3: Build**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift build`
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add Renamer/Sources/Renamer/PresetStore.swift Renamer/Sources/Renamer/RenameSession.swift
git commit -m "feat(app): preset persistence and session wiring"
```

---

## Task 9: Presets UI bar in ControlsPanel

A presets row at the top of the controls: a menu to pick/apply a preset, and management actions (save as / rename / delete) driven by a name-entry alert.

**Files:**
- Modify: `Renamer/Sources/Renamer/ControlsPanel.swift`

- [ ] **Step 1: Add preset UI state and the bar**

In `Renamer/Sources/Renamer/ControlsPanel.swift`, add state properties at the top of `struct ControlsPanel` (after the `@EnvironmentObject` line):
```swift
    @State private var showNameDialog = false
    @State private var nameDialogText = ""
    @State private var nameDialogMode: NameDialogMode = .saveNew

    private enum NameDialogMode { case saveNew, rename }
```

Add the presets bar as the first child of the outer `VStack` (before the "Nowa nazwa" `HStack`, i.e. right after `VStack(alignment: .leading, spacing: 10) {`):
```swift
            HStack(spacing: 8) {
                Text("Schemat")
                    .frame(width: 90, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Menu(selectedPresetName) {
                    if session.presets.isEmpty {
                        Text("Brak zapisanych schematów").disabled(true)
                    }
                    ForEach(session.presets) { preset in
                        Button(preset.name) { session.applyPreset(preset) }
                    }
                }
                .fixedSize()

                Button("Zapisz jako…") {
                    nameDialogMode = .saveNew
                    nameDialogText = ""
                    showNameDialog = true
                }
                Button("Zmień nazwę…") {
                    nameDialogMode = .rename
                    nameDialogText = selectedPreset?.name ?? ""
                    showNameDialog = true
                }
                .disabled(selectedPreset == nil)
                Button("Usuń") {
                    if let id = session.selectedPresetID { session.deletePreset(id: id) }
                }
                .disabled(selectedPreset == nil)
                Spacer()
            }
```

- [ ] **Step 2: Add the name dialog and helpers**

In `Renamer/Sources/Renamer/ControlsPanel.swift`, add the `.alert` modifier to the outer `VStack` — attach it right after `.background(Color(nsColor: .windowBackgroundColor))` (the existing last modifier of the body `VStack`):
```swift
        .alert(nameDialogMode == .saveNew ? "Zapisz schemat" : "Zmień nazwę schematu",
               isPresented: $showNameDialog) {
            TextField("Nazwa schematu", text: $nameDialogText)
            Button("Anuluj", role: .cancel) {}
            Button("Zapisz") {
                switch nameDialogMode {
                case .saveNew:
                    session.saveCurrentAsPreset(name: nameDialogText)
                case .rename:
                    if let id = session.selectedPresetID {
                        session.renamePreset(id: id, to: nameDialogText)
                    }
                }
            }
        }
```

Add these computed helpers inside `struct ControlsPanel` (after `body`):
```swift
    private var selectedPreset: Preset? {
        session.presets.first { $0.id == session.selectedPresetID }
    }

    private var selectedPresetName: String {
        selectedPreset?.name ?? "Wybierz schemat"
    }
```

Add the import for `Preset` type — `RenamerCore` is already imported at the top of the file, so no change needed.

- [ ] **Step 3: Build**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift build`
Expected: `Build complete!`.

- [ ] **Step 4: Manual verification**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift run Renamer`
Then:
1. Drag in a file. Set template `photo_{counter:001}`. Click "Zapisz jako…", type `Zdjęcia`, Zapisz. The "Schemat" menu now shows `Zdjęcia` as selected.
2. Change template to something else, then pick `Zdjęcia` from the menu → fields reset to the saved scheme; preview updates.
3. "Zmień nazwę…" → `Foto`; the menu label updates to `Foto`.
4. Quit the app (Cmd+Q) and relaunch (`swift run Renamer`); `Foto` is still in the menu (persisted).
5. "Usuń" removes it.

- [ ] **Step 5: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add Renamer/Sources/Renamer/ControlsPanel.swift
git commit -m "feat(app): presets UI (pick/save/rename/delete)"
```

---

## Task 10: Success banner + failure report

Add success/failure state to the session, update `apply`/`undoLast`, and render a top success banner plus a failure sheet.

**Files:**
- Modify: `Renamer/Sources/Renamer/RenameSession.swift`
- Create: `Renamer/Sources/Renamer/ResultBanner.swift`
- Create: `Renamer/Sources/Renamer/FailureReportSheet.swift`
- Modify: `Renamer/Sources/Renamer/ContentView.swift`

- [ ] **Step 1: Add result state + types to RenameSession**

In `Renamer/Sources/Renamer/RenameSession.swift`, add these types at file scope (after the `PreviewSortKey` enum, before `RenameSession`):
```swift
struct SuccessBanner: Equatable {
    let count: Int
}

struct FailureLine: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let message: String
}

struct FailureReport: Identifiable, Equatable {
    let id = UUID()
    let successCount: Int
    let failures: [FailureLine]
}
```

Add published properties after `showOverwriteAlert` (line 35):
```swift
    @Published var successBanner: SuccessBanner?
    @Published var failureReport: FailureReport?
```

Add a banner task field after `private var debounceTask` (line 40):
```swift
    private var bannerTask: Task<Void, Never>?
```

- [ ] **Step 2: Update `apply(overwrite:)`**

Replace `apply(overwrite:)` (lines 130-151) with:
```swift
    func apply(overwrite: Bool) {
        guard canApply else { return }
        isApplying = true
        defer { isApplying = false }

        do {
            let toApply = displayedRows().filter { $0.status != .error && $0.proposedName != $0.item.fullName }
            let result = try engine.apply(rows: displayedRows(), overwrite: overwrite)
            if result.failures.isEmpty {
                undoBatch = result.undo
                canUndo = true
                items = FileItemLoader.load(items.map(\.url))
                statusMessage = "Zmieniono \(toApply.count) plik(ów)."
                showSuccessBanner(count: toApply.count)
            } else {
                let lines = result.failures.map {
                    FailureLine(name: $0.move.to.lastPathComponent, message: $0.message)
                }
                let succeeded = max(0, toApply.count - result.failures.count)
                failureReport = FailureReport(successCount: succeeded, failures: lines)
                statusMessage = "Błędy: \(result.failures.count)"
                undoBatch = result.undo
                canUndo = !result.undo.moves.isEmpty
                items = FileItemLoader.load(items.map(\.url))
            }
            rebuildPlan()
        } catch {
            failureReport = FailureReport(successCount: 0,
                                          failures: [FailureLine(name: "—", message: error.localizedDescription)])
            statusMessage = "Błąd: \(error.localizedDescription)"
        }
    }

    private func showSuccessBanner(count: Int) {
        bannerTask?.cancel()
        successBanner = SuccessBanner(count: count)
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.successBanner = nil
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        successBanner = nil
    }
```

In `undoLast()` (lines 153-165), add banner dismissal — replace the body's success path so it also clears the banner. Replace:
```swift
            try undoBatch.undo()
            self.undoBatch = nil
            canUndo = false
            items = FileItemLoader.load(items.map(\.url))
            statusMessage = "Cofnięto ostatnią operację."
            rebuildPlan()
```
with:
```swift
            try undoBatch.undo()
            self.undoBatch = nil
            canUndo = false
            dismissBanner()
            items = FileItemLoader.load(items.map(\.url))
            statusMessage = "Cofnięto ostatnią operację."
            rebuildPlan()
```

- [ ] **Step 3: Create ResultBanner**

Create `Renamer/Sources/Renamer/ResultBanner.swift`:
```swift
import SwiftUI

struct ResultBanner: View {
    @EnvironmentObject private var session: RenameSession
    let banner: SuccessBanner

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Zmieniono \(banner.count) plik(ów)")
                .foregroundStyle(.white)
                .fontWeight(.semibold)
            Spacer()
            Button("Cofnij") { session.undoLast() }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .disabled(!session.canUndo)
            Button {
                session.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .shadow(radius: 6)
    }
}
```

- [ ] **Step 4: Create FailureReportSheet**

Create `Renamer/Sources/Renamer/FailureReportSheet.swift`:
```swift
import SwiftUI

struct FailureReportSheet: View {
    @EnvironmentObject private var session: RenameSession
    let report: FailureReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Część operacji nie powiodła się")
                .font(.headline)
            Text("Zmieniono: \(report.successCount) · Błędy: \(report.failures.count)")
                .foregroundStyle(.secondary)
            List(report.failures) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(line.message)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160)
            HStack {
                Spacer()
                Button("OK") { session.failureReport = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
```

- [ ] **Step 5: Wire banner overlay + failure sheet into ContentView**

In `Renamer/Sources/Renamer/ContentView.swift`, replace the body's outer `VStack { ... }` closing and its `.alert` modifier (lines 9-29) so the overlay and sheet are attached. Replace:
```swift
        VStack(spacing: 0) {
            header
            Divider()
            if session.items.isEmpty {
                DropZoneView()
            } else {
                ControlsPanel()
                Divider()
                PreviewTable()
            }
            Divider()
            FooterBar()
        }
        .alert("Nadpisać istniejące pliki?", isPresented: $session.showOverwriteAlert) {
            Button("Anuluj", role: .cancel) {}
            Button("Kontynuuj", role: .destructive) {
                session.apply(overwrite: true)
            }
        } message: {
            Text("\(session.warningCount) plik(ów) zostanie nadpisanych. Kontynuować?")
        }
```
with:
```swift
        VStack(spacing: 0) {
            header
            Divider()
            if session.items.isEmpty {
                DropZoneView()
            } else {
                ControlsPanel()
                Divider()
                PreviewTable()
            }
            Divider()
            FooterBar()
        }
        .overlay(alignment: .top) {
            if let banner = session.successBanner {
                ResultBanner(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.successBanner)
        .sheet(item: $session.failureReport) { report in
            FailureReportSheet(report: report)
        }
        .alert("Nadpisać istniejące pliki?", isPresented: $session.showOverwriteAlert) {
            Button("Anuluj", role: .cancel) {}
            Button("Kontynuuj", role: .destructive) {
                session.apply(overwrite: true)
            }
        } message: {
            Text("\(session.warningCount) plik(ów) zostanie nadpisanych. Kontynuować?")
        }
```

- [ ] **Step 6: Build**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift build`
Expected: `Build complete!`.

- [ ] **Step 7: Manual verification**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift run Renamer`
Then:
1. Drag in two files in a writable folder. Set template `ok_{counter:01}`. Click "Zmień nazwy". A green banner "Zmieniono 2 plik(ów)" slides in at the top with a "Cofnij" button, and disappears on its own after ~4 s.
2. Click "Cofnij" in the banner before it fades → files revert, banner disappears.
3. To see the failure sheet: create a read-only situation — e.g., add a file whose target name duplicates an existing on-disk file and force overwrite into a folder where the move fails, or temporarily make the folder read-only (`chmod 500`). Apply → a sheet "Część operacji nie powiodła się" lists the failed file(s) and a reason; "OK" dismisses it. Restore permissions afterward (`chmod 755`).

- [ ] **Step 8: Commit**

```bash
cd /Users/micz/__DEV__/__renamer
git add Renamer/Sources/Renamer/RenameSession.swift Renamer/Sources/Renamer/ResultBanner.swift Renamer/Sources/Renamer/FailureReportSheet.swift Renamer/Sources/Renamer/ContentView.swift
git commit -m "feat(app): success banner and failure report sheet"
```

---

## Task 11: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Run the full core test suite**

Run: `cd /Users/micz/__DEV__/__renamer/RenamerCore && swift test`
Expected: PASS — every test, 0 failures (includes `LockExtensionTests`, `ReplaceTokensTests`, `ConfigCodableTests`, `PresetManagerTests`, and all pre-existing tests).

- [ ] **Step 2: Build the app cleanly**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift build`
Expected: `Build complete!` with no warnings about the removed `TokenInsertMenu`.

- [ ] **Step 3: End-to-end manual smoke**

Run: `cd /Users/micz/__DEV__/__renamer/Renamer && swift run Renamer`
Confirm in one session:
1. Lock extension ON by default; extension case picker disabled; `.jpg` preserved under name-case changes.
2. Replace field accepts `{counter:001}` and numbers per file in the preview.
3. Regex mode shows the Search "Wyrażenie" menu, the cheat-sheet line, and `$1`/`$2`/`$3` in the Replace insert menu.
4. Save a preset, switch away, re-apply it, rename it, relaunch (persisted), delete it.
5. Apply a rename → green success banner with working "Cofnij"; auto-dismiss after ~4 s.

- [ ] **Step 4: Final commit (if any tracked changes remain)**

```bash
cd /Users/micz/__DEV__/__renamer
git status
# If anything is uncommitted:
git add -A && git commit -m "chore: renamer v2 features verification pass"
```

---

## Self-Review

**Spec coverage (spec §4–§9):**
- §4 confirmation (banner + failure sheet, auto-dismiss, undo) → Task 10.
- §5 lock extension (default on, base-only pipeline, extCase disabled, persistence) → Tasks 1, 5, 6.
- §6 presets (Codable, Preset, PresetManager, PresetStore, session wiring, UI add/delete/rename, apply, persistence) → Tasks 3, 4, 8, 9.
- §7 helpers (mode picker → isRegex, Search regex menu + cheat sheet, Replace variable menu + groups, per-file replacement token expansion) → Tasks 2, 6, 7.
- §8 file map → matches the Tasks' Create/Modify lists.
- §9 testing (core TDD + app build/manual) → Tasks 1–4 (TDD), 5–11 (build + manual).

**Placeholder scan:** No TBD/TODO. Every code step shows complete code; every run step has an exact command and expected result; manual steps give concrete inputs and observable outcomes.

**Type consistency:**
- `RenameConfig.init(..., lockExtension: Bool = false)` defined Task 1; used with `lockExtension:` in Tasks 5, 8 and in core tests Tasks 1–4.
- `FindReplace(search:replacement:isRegex:caseSensitive:)` unchanged — used consistently in `currentConfig` (Task 8) and `rebuildPlanNow` (Task 5).
- Session methods: `insertToken` / `insertReplacementToken` / `insertSearchToken` (Task 7) used by menus (Task 7); `loadConfig`, `applyPreset`, `saveCurrentAsPreset`, `deletePreset(id:)`, `renamePreset(id:to:)` (Task 8) used by UI (Task 9); `currentConfig` (Task 8) used by `saveCurrentAsPreset`.
- Result types `SuccessBanner`, `FailureReport`, `FailureLine` (Task 10) used by `ResultBanner`/`FailureReportSheet`/`ContentView` (Task 10); `dismissBanner()` used by banner + undo.
- `PresetManager.add/delete(id:from:)/rename(id:to:in:)` (Task 4) used by session (Task 8).
- `MoveFailure.move.to` and `UndoBatch.moves` (existing core API) used in Task 10 — confirmed against `RenameExecutor.swift`.

**One caveat flagged in spec:** a token expanding to a literal `$` in regex mode can be misread as a group backref — documented limitation, not handled in v2.
