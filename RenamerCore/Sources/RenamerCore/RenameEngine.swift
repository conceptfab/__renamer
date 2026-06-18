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
