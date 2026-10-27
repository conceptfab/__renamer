import Foundation

/// One intended rename, or one recorded physical move (reused for both).
public struct Move: Equatable, Sendable {
    public let from: URL
    public let to: URL
    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
    }
}

public struct MoveFailure: Equatable, Sendable {
    public let move: Move
    public let message: String
}

/// One renamed file as undo sees it.
public struct UndoEntry: Equatable, Sendable {
    /// Name before the rename.
    public let original: URL
    /// Where the file is now: its new name, or a hidden temp name if a restore failed.
    public let current: URL
}

/// Records what a rename did so it can be reversed, file by file.
/// `@unchecked`: FileManager is not marked Sendable, but its move/trash calls are
/// thread-safe (no delegate is used), and undo runs off the main actor.
public struct UndoBatch: @unchecked Sendable {
    public let entries: [UndoEntry]
    /// Items moved to the Trash to make room: `from` = where they were, `to` = their URL in the Trash.
    public let trashed: [Move]
    private let fileManager: FileManager

    public init(entries: [UndoEntry], trashed: [Move] = [], fileManager: FileManager = .default) {
        self.entries = entries
        self.trashed = trashed
        self.fileManager = fileManager
    }

    public var isEmpty: Bool { entries.isEmpty && trashed.isEmpty }

    /// Best-effort undo: every file is reversed on its own and a failure does not stop
    /// the rest. A file that cannot get its old name back stays at its current visible
    /// name; it and any un-restored trashed item are kept in `remaining` for a retry.
    public func undo() -> UndoOutcome {
        var failures: [MoveFailure] = []
        var remaining: [UndoEntry] = []
        var restored: [Move] = []

        // Phase 1: move every file off its new name to a temp first, so cycles (a <-> b) resolve.
        var staged: [(entry: UndoEntry, temp: URL)] = []
        for entry in entries.reversed() {
            if RenameExecutor.isTempName(entry.current.lastPathComponent) {
                staged.append((entry, entry.current))
                continue
            }
            let temp = entry.current.deletingLastPathComponent()
                .appendingPathComponent(RenameExecutor.tempName(for: entry.original.lastPathComponent))
            do {
                try fileManager.moveItem(at: entry.current, to: temp)
                staged.append((entry, temp))
            } catch {
                failures.append(MoveFailure(move: Move(from: entry.current, to: entry.original),
                                            message: error.localizedDescription))
                remaining.append(entry)
            }
        }

        // Phase 2: temp -> original name. On failure go back to the visible name.
        for (entry, temp) in staged {
            let message: String
            if fileManager.fileExists(atPath: entry.original.path) {
                message = "Cel istnieje"
            } else {
                do {
                    try fileManager.moveItem(at: temp, to: entry.original)
                    restored.append(Move(from: entry.current, to: entry.original))
                    continue
                } catch {
                    message = error.localizedDescription
                }
            }
            failures.append(MoveFailure(move: Move(from: entry.current, to: entry.original), message: message))
            if temp != entry.current, (try? fileManager.moveItem(at: temp, to: entry.current)) != nil {
                remaining.append(entry)
            } else {
                remaining.append(UndoEntry(original: entry.original, current: temp))
            }
        }

        // Phase 3: bring trashed items back once their place is free again.
        var remainingTrashed: [Move] = []
        for item in trashed.reversed() {
            if fileManager.fileExists(atPath: item.from.path) {
                failures.append(MoveFailure(move: Move(from: item.to, to: item.from), message: "Cel istnieje"))
                remainingTrashed.append(item)
                continue
            }
            do {
                try fileManager.moveItem(at: item.to, to: item.from)
            } catch {
                failures.append(MoveFailure(move: Move(from: item.to, to: item.from),
                                            message: error.localizedDescription))
                remainingTrashed.append(item)
            }
        }

        return UndoOutcome(restored: restored, failures: failures,
                           remaining: UndoBatch(entries: remaining.reversed(),
                                                trashed: remainingTrashed.reversed(),
                                                fileManager: fileManager))
    }
}

public struct UndoOutcome: Sendable {
    /// Files that got their old name back: `from` = name before undo, `to` = restored name.
    public let restored: [Move]
    public let failures: [MoveFailure]
    /// What could not be undone; undo it again to retry.
    public let remaining: UndoBatch
}

public struct ExecutionResult {
    public let undo: UndoBatch
    public let failures: [MoveFailure]
    /// Renames that actually completed, as original source -> final target.
    public let successfulRenames: [Move]
}

public struct RenameExecutor {
    static let tempPrefix = ".renamer-tmp-"

    private let fileManager: FileManager
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Hidden temp name that still carries the original name (truncated to fit the
    /// name limit), so a file stranded by a crash mid-batch can be recovered by hand.
    static func tempName(for original: String) -> String {
        let head = tempPrefix + UUID().uuidString + "-"
        var kept = ""
        for ch in original {
            guard CollisionDetector.fitsLength(head + kept + String(ch)) else { break }
            kept.append(ch)
        }
        return head + kept
    }

    public static func isTempName(_ name: String) -> Bool { name.hasPrefix(tempPrefix) }

    /// A rename must stay in the source's folder under a valid name ("dir/.." would
    /// otherwise point at the parent folder).
    static func staysInDirectory(_ move: Move) -> Bool {
        guard CollisionDetector.isValidName(move.to.lastPathComponent) else { return false }
        // No standardizedFileURL: it drops "/private" only from paths that exist.
        return move.to.deletingLastPathComponent().path == move.from.deletingLastPathComponent().path
    }

    /// Two-phase rename: sources -> temp, then temp -> final target.
    /// On any phase-2 failure the temp is restored to its original name so no
    /// file is ever left orphaned under a hidden temporary name.
    public func execute(_ moves: [Move], overwrite: Bool) throws -> ExecutionResult {
        var entries: [UndoEntry] = []
        var trashed: [Move] = []
        var failures: [MoveFailure] = []
        var successfulRenames: [Move] = []
        // Files of this batch, never trashed: sources that could not be moved aside
        // and files already placed at their final name.
        var batchFiles = Set<String>()

        // Phase 1: move each source to a unique temp name in its own directory.
        var temps: [(temp: URL, final: URL, original: URL)] = []
        for move in moves {
            guard Self.staysInDirectory(move) else {
                failures.append(MoveFailure(move: move, message: "Niedozwolona nazwa"))
                batchFiles.insert(CollisionDetector.pathKey(move.from))
                continue
            }
            let temp = move.from.deletingLastPathComponent()
                .appendingPathComponent(Self.tempName(for: move.from.lastPathComponent))
            do {
                try fileManager.moveItem(at: move.from, to: temp)
                temps.append((temp: temp, final: move.to, original: move.from))
            } catch {
                failures.append(MoveFailure(move: move, message: error.localizedDescription))
                batchFiles.insert(CollisionDetector.pathKey(move.from))
            }
        }

        // Phase 2: move each temp to its final target.
        for entry in temps {
            let move = Move(from: entry.original, to: entry.final)
            do {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: entry.final.path, isDirectory: &isDir) {
                    // Folders are never trashed; neither are files of this batch.
                    let message: String? = isDir.boolValue ? "Istnieje folder o tej nazwie"
                        : (!overwrite || batchFiles.contains(CollisionDetector.pathKey(entry.final))) ? "Cel istnieje"
                        : nil
                    if let message {
                        failures.append(MoveFailure(move: move, message: message + restore(entry, &entries)))
                        continue
                    }
                    var trashURL: NSURL?
                    try fileManager.trashItem(at: entry.final, resultingItemURL: &trashURL)
                    if let trashURL = trashURL as URL? {
                        trashed.append(Move(from: entry.final, to: trashURL))
                    }
                }
                try fileManager.moveItem(at: entry.temp, to: entry.final)
                entries.append(UndoEntry(original: entry.original, current: entry.final))
                successfulRenames.append(move)
                batchFiles.insert(CollisionDetector.pathKey(entry.final))
            } catch {
                failures.append(MoveFailure(move: move, message: error.localizedDescription + restore(entry, &entries)))
            }
        }

        return ExecutionResult(undo: UndoBatch(entries: entries, trashed: trashed, fileManager: fileManager),
                               failures: failures,
                               successfulRenames: successfulRenames)
    }

    /// Reverse a phase-1 move so the file returns to its original name.
    /// Best-effort: if the reversal itself fails, the file stays at its temp
    /// name and is recorded in `entries` so a later undo can still recover it.
    /// Returns a note naming that temp file for the failure message ("" on success).
    private func restore(_ entry: (temp: URL, final: URL, original: URL),
                         _ entries: inout [UndoEntry]) -> String {
        do {
            try fileManager.moveItem(at: entry.temp, to: entry.original)
            return ""
        } catch {
            entries.append(UndoEntry(original: entry.original, current: entry.temp))
            return " (plik pozostał pod nazwą tymczasową: \(entry.temp.lastPathComponent))"
        }
    }
}
