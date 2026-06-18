import SwiftUI

struct ResultBanner: View {
    @EnvironmentObject private var session: RenameSession
    let banner: SuccessBanner

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Zmieniono \(banner.count) plik(ów)")
                .foregroundStyle(.white)
                .fontWeight(.semibold)
            Spacer()
            Button("Cofnij") { session.undoLast() }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .disabled(!session.canUndo)
            Button {
                session.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
