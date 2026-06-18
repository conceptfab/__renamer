import SwiftUI

struct FooterBar: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        HStack {
            Text(session.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Cofnij ostatnią") {
                session.undoLast()
            }
            .disabled(!session.canUndo)
            Button("Zmień nazwy") {
                session.requestApply()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!session.canApply)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
