import SwiftUI

struct ResultBanner: View {
    @EnvironmentObject private var session: RenameSession
    let banner: SuccessBanner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Zmienione pliki: \(banner.count)")
                .fontWeight(.medium)
            Spacer()
            Button("Cofnij") { session.undoLast() }
                .buttonStyle(.borderless)
                .disabled(!session.canUndo || session.isApplying)
            Button {
                session.dismissBanner()
            } label: {
                Label("Zamknij powiadomienie", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .padding(16)
    }
}
