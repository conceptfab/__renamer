import Foundation

public enum CollisionDetector {
    /// Longest file name APFS accepts, in UTF-16 units of its decomposed (NFD) form.
    public static let maxNameUnits = 255

    static func fitsLength(_ name: String) -> Bool {
        name.decomposedStringWithCanonicalMapping.utf16.count <= maxNameUnits
    }

    /// APFS compares names case-insensitively with full folding (ß = ss, Σ = σ = ς).
    static func pathKey(_ url: URL) -> String {
        url.path.folding(options: .caseInsensitive, locale: nil)
    }

    /// "." and ".." resolve to the folder itself / its parent, so renaming onto them
    /// would target (and with overwrite, trash) a folder. Dotfiles like ".env" are fine.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains(":") && !name.contains("\0")
            && fitsLength(name)
    }

    public static func annotate(_ rows: [RenameRow], probe: FileSystemProbe) -> [RenameRow] {
        var out = rows
        let sourcePaths = Set(rows.map { pathKey($0.item.url) })

        // 1. Per-row name validation. Rows that already failed evaluation stay errors.
        for i in out.indices where out[i].status != .error {
            if !isValidName(out[i].proposedName) {
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
            let key = pathKey(out[i].targetURL)
            groups[key, default: []].append(i)
        }
        for (_, indices) in groups where indices.count > 1 {
            for i in indices {
                out[i].status = .error
                out[i].message = "Duplikat nazwy"
            }
        }

        // 3. Existing-on-disk warning (skip if the target is one of our sources).
        //    An existing folder is an error: overwrite never trashes folders.
        for i in out.indices where out[i].status == .ok {
            let target = out[i].targetURL
            if probe.exists(target), !sourcePaths.contains(pathKey(target)) {
                if probe.isDirectory(target) {
                    out[i].status = .error
                    out[i].message = "Istnieje folder o tej nazwie"
                } else {
                    out[i].status = .warning
                    out[i].message = "Plik już istnieje"
                }
            }
        }
        return out
    }
}
