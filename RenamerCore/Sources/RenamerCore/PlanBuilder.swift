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
}
