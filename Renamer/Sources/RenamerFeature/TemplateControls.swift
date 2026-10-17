import SwiftUI

struct TemplateControls: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("np. zdjęcie_{counter:001}", text: $session.template)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .controlSize(.large)
                .accessibilityLabel("Szablon nowej nazwy")
                .help("Szablon nowej nazwy. Puste pole zachowuje obecną nazwę.")
                .onChange(of: session.template) { _ in session.onConfigChanged() }

            HStack {
                Spacer()
                VariableInsertMenu { session.insertToken($0, into: \.template) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
