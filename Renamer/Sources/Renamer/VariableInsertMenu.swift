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
