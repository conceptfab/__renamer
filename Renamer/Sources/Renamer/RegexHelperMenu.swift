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
