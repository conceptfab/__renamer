import SwiftUI

struct FooterBar: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        HStack(spacing: 8) {
            if !session.items.isEmpty {
                Image(systemName: session.errorCount > 0 ? "exclamationmark.circle" : "doc.on.doc")
                    .foregroundStyle(.secondary)
                Text(session.statusMessage)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(session.statusMessage)
                    .lineLimit(1)
            }
            Spacer()
            if !session.items.isEmpty {
                Button("Wyczyść listę", action: session.removeAll)
                    .buttonStyle(.borderless)
                    .disabled(session.isApplying)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
