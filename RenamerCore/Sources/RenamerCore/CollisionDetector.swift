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
