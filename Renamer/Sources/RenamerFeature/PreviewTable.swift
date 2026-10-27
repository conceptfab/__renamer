import SwiftUI
import RenamerCore

private struct PreviewRow: Identifiable {
    let id: String
    let row: RenameRow

    init(_ row: RenameRow) {
        self.row = row
        id = row.item.url.path
    }
}

struct PreviewTable: View {
    @EnvironmentObject private var session: RenameSession

    private var previewRows: [PreviewRow] {
        session.rows.map(PreviewRow.init)
    }

    var body: some View {
        Table(previewRows) {
            TableColumn("Obecna nazwa") { item in
                Label {
                    Text(item.row.item.fullName)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "doc")
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
                .help(item.row.item.url.path)
                .padding(.vertical, 5)
            }
            .width(min: 180, ideal: 240)

            TableColumn("") { _ in
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .width(20)

            TableColumn("Nowa nazwa") { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.row.proposedName)
                            .fontWeight(item.row.proposedName != item.row.item.fullName ? .medium : .regular)
                            .lineLimit(1)
                        if let message = item.row.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    statusBadge(for: item.row)
                }
                .padding(.vertical, 5)
                .help(item.row.message ?? item.row.proposedName)
            }
            .width(min: 220, ideal: 320)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }

    @ViewBuilder
    private func statusBadge(for row: RenameRow) -> some View {
        switch row.status {
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Błąd")
                .help(row.message ?? "Błąd")
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Ostrzeżenie")
                .help(row.message ?? "Ostrzeżenie")
        case .ok:
            EmptyView()
        }
    }
}
