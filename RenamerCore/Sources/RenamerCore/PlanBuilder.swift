import Foundation

public struct PlanBuilder {
    /// Default wall-clock budget for building one plan. Only a runaway regex match can
    /// hit it (normal plans take milliseconds); it keeps a bad pattern from hanging the app.
    public static let defaultTimeBudget: TimeInterval = 2

    static let slowRegexMessage = "Wyrażenie regularne zbyt wolne"

    private let evaluator: TemplateEvaluator

    public init(evaluator: TemplateEvaluator = TemplateEvaluator()) {
        self.evaluator = evaluator
    }

    /// The config parsed/compiled once per plan instead of once per file.
    private struct Prepared {
        let config: RenameConfig
        let templateSegments: [TemplateSegment]?   // nil: empty template
        let replacementSegments: [TemplateSegment]
        let find: FindReplace.Compiled?            // nil: no search term

        init(_ config: RenameConfig) throws {
            self.config = config
            templateSegments = config.template.isEmpty ? nil : try TemplateParser.parse(config.template)
            // Skip when there is no search term — the replacement would never be
            // applied, so we must not parse it (avoids spurious errors).
            if config.find.search.isEmpty {
                replacementSegments = []
                find = nil
            } else {
                replacementSegments = try TemplateParser.parse(config.find.replacement)
                find = try config.find.compiled()
            }
        }
    }

    /// Runs the full pipeline for one file. Throws on template/regex errors.
    public func proposedName(for item: FileItem, index: Int, config: RenameConfig) throws -> String {
        try proposedName(for: item, index: index, prepared: Prepared(config), shouldStop: { false })
    }

    private func proposedName(for item: FileItem, index: Int, prepared: Prepared,
                              shouldStop: () -> Bool) throws -> String {
        let config = prepared.config
        // 1. Base. When locked, work on the name part only.
        let base: String
        if let segments = prepared.templateSegments {
            let evaluated = try evaluator.evaluate(segments, item: item, index: index)
            base = config.lockExtension ? NameComponents(fullName: evaluated).base : evaluated
        } else {
            base = config.lockExtension ? item.baseName : item.fullName
        }
        // 2. Find/replace. The replacement is a mini-template expanded per file
        //    so tokens like {counter} work; regex backrefs ($1) pass through.
        let replaced: String
        if let find = prepared.find {
            let expandedReplacement = try evaluator.evaluate(
                prepared.replacementSegments, item: item, index: index)
            replaced = try find.apply(to: base, replacement: expandedReplacement, shouldStop: shouldStop)
        } else {
            replaced = base
        }
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

    /// Builds annotated rows for all items in the given order. Counter indices
    /// follow array order, so callers sort `items` before calling.
    ///
    /// When `timeBudget` runs out (a runaway regex) the remaining rows are marked as
    /// errors. When the calling Task is cancelled the work stops early and the rows
    /// are meaningless — callers must discard them.
    public func build(items: [FileItem], config: RenameConfig, probe: FileSystemProbe,
                      timeBudget: TimeInterval? = PlanBuilder.defaultTimeBudget) -> [RenameRow] {
        let prepared: Prepared
        do {
            prepared = try Prepared(config)
        } catch {
            // A template parse error invalidates the whole batch; so does a bad
            // replacement or regex (it would fail identically for every file).
            let isTemplateError = (try? TemplateParser.parse(config.template)) == nil
            let message = isTemplateError ? "Błędny szablon" : "Błąd wyrażenia"
            return items.map {
                RenameRow(item: $0, proposedName: $0.fullName, status: .error, message: message)
            }
        }

        let deadline = timeBudget.map { Date().addingTimeInterval($0) }
        let shouldStop: () -> Bool = {
            Task.isCancelled || (deadline.map { Date() > $0 } ?? false)
        }

        var rows: [RenameRow] = []
        rows.reserveCapacity(items.count)
        var outOfTime = false
        for (index, item) in items.enumerated() {
            if outOfTime {
                rows.append(RenameRow(item: item, proposedName: item.fullName, status: .error,
                                      message: Self.slowRegexMessage))
                continue
            }
            if Task.isCancelled { return rows }
            do {
                let name = try proposedName(for: item, index: index, prepared: prepared, shouldStop: shouldStop)
                rows.append(RenameRow(item: item, proposedName: name, status: .ok, message: nil))
            } catch FindReplaceError.timedOut {
                if Task.isCancelled { return rows }
                outOfTime = true
                rows.append(RenameRow(item: item, proposedName: item.fullName, status: .error,
                                      message: Self.slowRegexMessage))
            } catch {
                rows.append(RenameRow(item: item, proposedName: item.fullName, status: .error,
                                      message: "Błąd wyrażenia"))
            }
        }
        return CollisionDetector.annotate(rows, probe: probe)
    }
}
