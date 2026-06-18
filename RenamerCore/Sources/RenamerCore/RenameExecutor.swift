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
