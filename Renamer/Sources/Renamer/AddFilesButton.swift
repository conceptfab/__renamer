import SwiftUI

struct AddFilesButton: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        Button {
            presentOpenFilesPanel(into: session)
        } label: {
            Label("Dodaj pliki", systemImage: "plus")
                .font(.body)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .keyboardShortcut("o", modifiers: .command)
        .help("Dodaj pliki (⌘O)")
    }
}
