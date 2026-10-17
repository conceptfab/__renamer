import SwiftUI

struct FailureReportSheet: View {
    @EnvironmentObject private var session: RenameSession
    let report: FailureReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Część operacji nie powiodła się")
                .font(.headline)
            Text("Zmieniono: \(report.successCount) · Błędy: \(report.failures.count)")
                .foregroundStyle(.secondary)
            List(report.failures) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(line.message)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160)
            HStack {
                Spacer()
                Button("OK") { session.failureReport = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
