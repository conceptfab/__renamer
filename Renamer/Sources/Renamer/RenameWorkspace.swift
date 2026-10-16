import SwiftUI

struct RenameWorkspace: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        VStack(spacing: 0) {
            if session.items.isEmpty {
                DropZoneView()
            } else {
                PreviewHeader()
                PreviewTable()
            }
            FooterBar()
        }
        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
