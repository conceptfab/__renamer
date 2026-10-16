import SwiftUI

struct TemplateControls: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        Group {
            TextField("np. zdjęcie_{counter:001}", text: $session.template)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .accessibilityLabel("Szablon nowej nazwy")
                .onChange(of: session.template) { _ in session.onConfigChanged() }

            HStack {
                Text("Zmienne")
                    .foregroundStyle(.secondary)
                Spacer()
                VariableInsertMenu { session.insertToken($0, into: \.template) }
            }
        }
    }
}
