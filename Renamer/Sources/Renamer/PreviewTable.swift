import SwiftUI
import RenamerCore

private struct PreviewRow: Identifiable {
    let id: String
    let row: RenameRow

    init(_ row: RenameRow) {
        self.row = row
        id = row.item.url.path + "|" + row.proposedName
    }
}

struct PreviewTable: View {
    @EnvironmentObject private var session: RenameSession

    private var previewRows: [PreviewRow] {
        session.displayedRows().map(PreviewRow.init)
    }

    var body: some View {
        Table(previewRows) {
            TableColumn("Stara nazwa") { item in
                Text(item.row.item.fullName)
                    .foregroundStyle(item.row.status == .error ? .primary : .secondary)
            }
            .width(min: 180, ideal: 240)

            TableColumn("→") { _ in
                Text("→")
                    .foregroundStyle(.tertiary)
            }
            .width(24)

            TableColumn("Nowa nazwa") { item in
                HStack(spacing: 6) {
                    Text(item.row.proposedName)
                        .fontWeight(item.row.proposedName != item.row.item.fullName ? .semibold : .regular)
                    statusBadge(for: item.row)
                    if let message = item.row.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 220, ideal: 320)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private func statusBadge(for row: RenameRow) -> some View {
        switch row.status {
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(row.message ?? "Błąd")
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(row.message ?? "Ostrzeżenie")
        case .ok:
            EmptyView()
        }
    }
}
