# Renamer v2 Audit Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the data-safety hazard where a partial rename failure orphans files under hidden temp names, report the true success count, and fix the latent multi-file drop crash.

**Architecture:** The fix lives almost entirely in `RenamerCore`'s `RenameExecutor`, which already does a safe two-phase rename (source → unique temp → final). We add a *restore* step so any phase-2 failure rolls that file back to its original name, and we expose the list of renames that actually completed so the UI can report an honest count. The SwiftUI layer is then a thin display change.

**Tech Stack:** Swift 5.9, Swift Package Manager, XCTest, SwiftUI/AppKit (macOS 13+). Two packages: `RenamerCore` (pure logic, tested) and `Renamer` (app, currently untested).

---

## Background: what the audit found

- **C1 (Critical, data loss):** `RenameExecutor.execute` ([RenameExecutor.swift:48-91](../../../RenamerCore/Sources/RenamerCore/RenameExecutor.swift#L48-L91)) moves every source to `.renamer-tmp-<uuid>` in phase 1. If phase 2 fails (target exists without `overwrite`, or `moveItem` throws), it leaves the file stuck at the hidden temp name — the original name is gone, with no in-app recovery.
- **C2 (Critical, trust):** [RenameSession.swift:224](../../../Renamer/Sources/Renamer/RenameSession.swift#L224) computes `succeeded = toApply.count - failures.count`, which is wrong on partial failure.
- **I2 (Important, latent crash):** [DropZoneView.swift:44-58](../../../Renamer/Sources/Renamer/DropZoneView.swift#L44-L58) appends to a shared `urls` array from concurrent `loadItem` completion handlers without synchronization.
- **M5 (Minor):** `apply` calls `displayedRows()` twice ([RenameSession.swift:211-212](../../../Renamer/Sources/Renamer/RenameSession.swift#L211-L212)).
- **M4 (Minor):** the `NSOpenPanel` setup is duplicated in `DropZoneView` and `ContentView`.

Deferred items (I3, I4, I5, I6, I7, M1, M3) are listed at the end with recommended approaches — they are not data-loss issues and are out of scope for this plan.

## File Structure

- **Modify** `RenamerCore/Sources/RenamerCore/RenameExecutor.swift` — add `successfulRenames` to `ExecutionResult`; track each entry's original source; add a `restore(...)` helper; call it on both phase-2 failure paths. (Task 1)
- **Modify** `RenamerCore/Tests/RenamerCoreTests/RenameExecutorTests.swift` — add failure-path and overwrite tests. (Task 1)
- **Modify** `Renamer/Sources/Renamer/RenameSession.swift` — report `result.successfulRenames.count`; label failures by source name; single `displayedRows()` call. (Task 2)
- **Modify** `Renamer/Sources/Renamer/DropZoneView.swift` — serialize the concurrent appends; call the shared open-panel helper. (Task 3, Task 4)
- **Create** `Renamer/Sources/Renamer/OpenFilesPanel.swift` — one shared open-panel helper. (Task 4)
- **Modify** `Renamer/Sources/Renamer/ContentView.swift` — call the shared open-panel helper. (Task 4)

---

## Task 1: Restore orphaned temps on phase-2 failure + expose actual successes (C1)

**Files:**
- Modify: `RenamerCore/Sources/RenamerCore/RenameExecutor.swift`
- Test: `RenamerCore/Tests/RenamerCoreTests/RenameExecutorTests.swift`

This is the core of the plan. Do it first; everything else depends on `ExecutionResult.successfulRenames`.

- [ ] **Step 1: Write the failing tests**

Append these three tests to `RenameExecutorTests.swift`, before the final closing `}` (they reuse the existing `write`, `read`, and `dir` helpers):

```swift
    func test_targetExistsWithoutOverwrite_restoresOriginal() throws {
        let a = try write("a.txt", "A")
        _ = try write("b.txt", "EXISTING")            // final target already on disk
        let moves = [Move(from: a, to: dir.appendingPathComponent("b.txt"))]
        let result = try RenameExecutor().execute(moves, overwrite: false)

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.message, "Cel istnieje")
        // Source restored to its original name, not left at a hidden temp name.
        XCTAssertEqual(read("a.txt"), "A")
        XCTAssertEqual(read("b.txt"), "EXISTING")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".renamer-tmp-") })
        // Net no-op: nothing succeeded, nothing to undo.
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
        _ = try write("c.txt", "EXISTING")            // blocks b -> c
        let moves = [
            Move(from: a, to: dir.appendingPathComponent("x.txt")),  // succeeds
            Move(from: b, to: dir.appendingPathComponent("c.txt")),  // fails: target exists
        ]
        let result = try RenameExecutor().execute(moves, overwrite: false)

        XCTAssertEqual(result.successfulRenames.count, 1)
        XCTAssertEqual(result.successfulRenames.first?.to.lastPathComponent, "x.txt")
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(read("x.txt"), "A")            // a renamed
        XCTAssertEqual(read("b.txt"), "B")            // b restored
        XCTAssertEqual(read("c.txt"), "EXISTING")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".renamer-tmp-") })
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd RenamerCore && swift test --filter RenameExecutorTests`
Expected: COMPILE FAILURE — `value of type 'ExecutionResult' has no member 'successfulRenames'`. (The member does not exist yet; that compile error is the "red".)

- [ ] **Step 3: Add `successfulRenames` to `ExecutionResult`**

In `RenameExecutor.swift`, replace the struct (currently lines 36-39):

```swift
public struct ExecutionResult {
    public let undo: UndoBatch
    public let failures: [MoveFailure]
}
```

with:

```swift
public struct ExecutionResult {
    public let undo: UndoBatch
    public let failures: [MoveFailure]
    /// Renames that actually completed, as original source -> final target.
    public let successfulRenames: [Move]
}
```

- [ ] **Step 4: Rewrite `execute` to restore on failure and record real successes**

In `RenameExecutor.swift`, replace the entire `execute(_:overwrite:)` method (currently lines 47-91) with:

```swift
    /// Two-phase rename: sources -> temp, then temp -> final target.
    /// On any phase-2 failure the temp is restored to its original name so no
    /// file is ever left orphaned under a hidden temporary name.
    public func execute(_ moves: [Move], overwrite: Bool) throws -> ExecutionResult {
        var performed: [Move] = []
        var failures: [MoveFailure] = []
        var successfulRenames: [Move] = []

        // Phase 1: move each source to a unique temp name in its own directory.
        var temps: [(temp: URL, final: URL, original: URL)] = []
        for move in moves {
            let temp = move.from.deletingLastPathComponent()
                .appendingPathComponent(".renamer-tmp-" + UUID().uuidString)
            do {
                try fileManager.moveItem(at: move.from, to: temp)
                performed.append(Move(from: move.from, to: temp))
                temps.append((temp: temp, final: move.to, original: move.from))
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
                        restore(entry, &performed)
                        failures.append(MoveFailure(
                            move: Move(from: entry.original, to: entry.final),
                            message: "Cel istnieje"))
                        continue
                    }
                }
                try fileManager.moveItem(at: entry.temp, to: entry.final)
                performed.append(Move(from: entry.temp, to: entry.final))
                successfulRenames.append(Move(from: entry.original, to: entry.final))
            } catch {
                restore(entry, &performed)
                failures.append(MoveFailure(
                    move: Move(from: entry.original, to: entry.final),
                    message: error.localizedDescription))
            }
        }

        return ExecutionResult(undo: UndoBatch(moves: performed, fileManager: fileManager),
                               failures: failures,
                               successfulRenames: successfulRenames)
    }

    /// Reverse a phase-1 move so the file returns to its original name.
    /// Best-effort: if the reversal itself fails, the file stays at its temp
    /// name and the source->temp move is left in `performed` so a later undo
    /// can still recover it.
    private func restore(_ entry: (temp: URL, final: URL, original: URL),
                         _ performed: inout [Move]) {
        do {
            try fileManager.moveItem(at: entry.temp, to: entry.original)
            performed.removeAll { $0 == Move(from: entry.original, to: entry.temp) }
        } catch {
            // Leave the temp in place; `performed` retains the source->temp move.
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd RenamerCore && swift test --filter RenameExecutorTests`
Expected: PASS — all `RenameExecutorTests` green (the 4 original + 3 new). Then run the full suite to confirm no regression: `cd RenamerCore && swift test`
Expected: PASS — all tests green.

- [ ] **Step 6: Commit**

```bash
git add RenamerCore/Sources/RenamerCore/RenameExecutor.swift RenamerCore/Tests/RenamerCoreTests/RenameExecutorTests.swift
git commit -m "fix(core): restore orphaned temps on partial rename failure

A phase-2 failure (target exists without overwrite, or moveItem throws)
previously left the file stuck at its .renamer-tmp-<uuid> name. Now the
temp is rolled back to the original name, and ExecutionResult exposes the
renames that actually completed.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Report the true success count and label failures by source (C2 + M5)

**Files:**
- Modify: `Renamer/Sources/Renamer/RenameSession.swift:205-238`

Note on testing: the `Renamer` app package has no test target, and `apply()` consumes `rows` produced by the **debounced** `rebuildPlan()`, so a session-level unit test would be flaky. The success-count logic now lives in `RenameExecutor` and is locked in by `test_partialFailure_reportsOnlyActualSuccesses` (Task 1). This task is a display change verified by building + the Task 1 test.

- [ ] **Step 1: Replace the body of `apply(overwrite:)`**

In `RenameSession.swift`, replace the whole method (currently lines 205-238):

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
                dismissBanner()
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
            dismissBanner()
            failureReport = FailureReport(successCount: 0,
                                          failures: [FailureLine(name: "—", message: error.localizedDescription)])
            statusMessage = "Błąd: \(error.localizedDescription)"
        }
    }
```

with:

```swift
    func apply(overwrite: Bool) {
        guard canApply else { return }
        isApplying = true
        defer { isApplying = false }

        do {
            let result = try engine.apply(rows: displayedRows(), overwrite: overwrite)
            let succeeded = result.successfulRenames.count
            if result.failures.isEmpty {
                undoBatch = result.undo
                canUndo = true
                items = FileItemLoader.load(items.map(\.url))
                statusMessage = "Zmieniono \(succeeded) plik(ów)."
                showSuccessBanner(count: succeeded)
            } else {
                dismissBanner()
                let lines = result.failures.map {
                    FailureLine(name: $0.move.from.lastPathComponent, message: $0.message)
                }
                failureReport = FailureReport(successCount: succeeded, failures: lines)
                statusMessage = "Błędy: \(result.failures.count)"
                undoBatch = result.undo
                canUndo = !result.undo.moves.isEmpty
                items = FileItemLoader.load(items.map(\.url))
            }
            rebuildPlan()
        } catch {
            dismissBanner()
            failureReport = FailureReport(successCount: 0,
                                          failures: [FailureLine(name: "—", message: error.localizedDescription)])
            statusMessage = "Błąd: \(error.localizedDescription)"
        }
    }
```

Three changes: `succeeded` now uses `result.successfulRenames.count` (C2); `displayedRows()` is called once (M5); failure lines are labeled by `$0.move.from.lastPathComponent` — after Task 1, `move.from` is the original source that still exists on disk, which is the file the user actually needs to see.

- [ ] **Step 2: Build to verify it compiles**

Run: `cd Renamer && swift build`
Expected: BUILD SUCCEEDED (no warnings about an unused `toApply`).

- [ ] **Step 3: Commit**

```bash
git add Renamer/Sources/Renamer/RenameSession.swift
git commit -m "fix(app): report true rename success count; label failures by source

Use ExecutionResult.successfulRenames for the count instead of
toApply.count - failures.count (wrong on partial failure), and show the
restored source name in the failure report. Collapses a double
displayedRows() call.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Fix the concurrent-append data race on multi-file drop (I2)

**Files:**
- Modify: `Renamer/Sources/Renamer/DropZoneView.swift:44-64`

`provider.loadItem` completion blocks run on arbitrary queues; appending to a shared `Array` from several of them at once is undefined behavior. Serialize the appends with a lock. (This is view + `NSItemProvider` glue and is verified by build + manual multi-file drop, not a unit test.)

- [ ] **Step 1: Replace `handleDrop`**

In `DropZoneView.swift`, replace the whole method (currently lines 44-64):

```swift
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            session.addURLs(urls)
        }
        return true
    }
```

with:

```swift
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let url = item as? URL {
                    resolved = url
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    resolved = url
                }
                guard let resolved else { return }
                lock.lock()
                urls.append(resolved)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            session.addURLs(urls)
        }
        return true
    }
```

`group.notify` already happens-after every `group.leave()`, so the read of `urls` on the main queue sees all locked writes.

- [ ] **Step 2: Build to verify it compiles**

Run: `cd Renamer && swift build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Renamer/Sources/Renamer/DropZoneView.swift
git commit -m "fix(app): serialize concurrent URL appends in drop handler

loadItem completions run on arbitrary queues; guard the shared array with
a lock to avoid a data race when dropping multiple files.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: De-duplicate the open-files panel (M4)

**Files:**
- Create: `Renamer/Sources/Renamer/OpenFilesPanel.swift`
- Modify: `Renamer/Sources/Renamer/DropZoneView.swift:23,33-42`
- Modify: `Renamer/Sources/Renamer/ContentView.swift:42-51,61`

Minor polish: `DropZoneView.openFiles()` and `ContentView.openMoreFiles()` are byte-for-byte identical. Extract one helper.

- [ ] **Step 1: Create the shared helper**

Create `Renamer/Sources/Renamer/OpenFilesPanel.swift`:

```swift
import AppKit

/// Presents the standard "open files" panel and feeds the chosen URLs to the
/// session. Shared by the drop zone and the toolbar "add files" button.
@MainActor
func presentOpenFilesPanel(into session: RenameSession) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.begin { response in
        guard response == .OK else { return }
        session.addURLs(panel.urls)
    }
}
```

- [ ] **Step 2: Use it from `DropZoneView`**

In `DropZoneView.swift`, change the button action (line 23) from:

```swift
                Button("Otwórz…") { openFiles() }
```

to:

```swift
                Button("Otwórz…") { presentOpenFilesPanel(into: session) }
```

Then delete the now-unused `private func openFiles()` (lines 33-42).

- [ ] **Step 3: Use it from `ContentView`**

In `ContentView.swift`, change the button action (line 61) from:

```swift
                Button("Dodaj pliki…") { openMoreFiles() }
```

to:

```swift
                Button("Dodaj pliki…") { presentOpenFilesPanel(into: session) }
```

Then delete the now-unused `private func openMoreFiles()` (lines 42-51).

- [ ] **Step 4: Build to verify it compiles**

Run: `cd Renamer && swift build`
Expected: BUILD SUCCEEDED (no "unused function" or "unresolved identifier" errors).

- [ ] **Step 5: Commit**

```bash
git add Renamer/Sources/Renamer/OpenFilesPanel.swift Renamer/Sources/Renamer/DropZoneView.swift Renamer/Sources/Renamer/ContentView.swift
git commit -m "refactor(app): share one open-files panel helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Run the full core test suite**

Run: `cd RenamerCore && swift test`
Expected: PASS — 81 tests (78 prior + 3 new), 0 failures.

- [ ] **Build the app**

Run: `cd Renamer && swift build`
Expected: BUILD SUCCEEDED.

- [ ] **Manual smoke test (data-safety path)**

1. Launch the app, drop two files `a.txt` and `b.txt`, plus a pre-existing `c.txt`.
2. Configure a rename that maps `b.txt` → `c.txt` (collision) and `a.txt` → `x.txt`.
3. Apply *without* overwrite.
4. Confirm: `a.txt` became `x.txt`, `b.txt` is **still `b.txt`** (not a hidden `.renamer-tmp-*`), `c.txt` untouched, the failure sheet shows "Zmieniono: 1" and lists `b.txt`.

---

## Deferred / decisions (not in this plan)

These are real but lower-priority (none is a data-loss path). Each needs its own plan or a product decision.

- **I6 — `engine.plan` runs on the MainActor** ([RenameSession.swift:283-294](../../../Renamer/Sources/Renamer/RenameSession.swift#L283-L294)). For thousands of files + a complex regex this can stutter the UI. Recommended approach: run `engine.plan` in a detached `Task`, assign `rows` back on the main actor. Requires confirming `FileItem`/`RenameConfig` are `Sendable`. Non-blocking for v2-sized batches.
- **I7 — `CollisionDetector` assumes a case-insensitive volume** ([CollisionDetector.swift:7,23,35](../../../RenamerCore/Sources/RenamerCore/CollisionDetector.swift#L7)). On a case-*sensitive* APFS volume it would falsely flag `a.txt` and `A.txt` as duplicates and block a legal rename. It errs in the safe direction (over-warns, never loses data). Fix: probe `URLResourceValues.volumeSupportsCaseSensitiveNames` and key collisions accordingly.
- **I3 — folders are silently dropped** ([RenameSession.swift:108-111](../../../Renamer/Sources/Renamer/RenameSession.swift#L108-L111)). Recommended: when the input contained a directory but `added` is empty, set `statusMessage` to explain folders aren't supported yet.
- **I4 — symlink behavior is undocumented/untested.** Renaming a symlink renames the link, not its target (probably intended). Add a regression test asserting a token producing `../x` is rejected (currently caught by the `/` check in `CollisionDetector.swift:11`).
- **I5 — user regex has no ReDoS guard** ([FindReplace.swift:28](../../../RenamerCore/Sources/RenamerCore/FindReplace.swift#L28)). Practically bounded by short filenames. Consider a comment acknowledging it; a real fix runs matching on a background queue with a cap.
- **M1 — build script signs ad-hoc** (`codesign --sign -` in `Renamer/scripts/build-app.sh`). Decision needed: wire Developer ID + notarization for distribution, or relabel the artifact as a local-only dev build. The original spec calls for notarization.
- **M3 — Polish error strings leak into the pure core** (e.g. `CollisionDetector.swift:13,29`, `RenameExecutor.swift:76`). Cleaner separation: core returns error *codes*, the app localizes. Larger refactor; defer until localization is actually on the roadmap.
