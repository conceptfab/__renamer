import SwiftUI

struct FindReplaceControls: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Tryb wyszukiwania", selection: $session.isRegex) {
                Text("Tekst").tag(false)
                Text("Regex").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: session.isRegex) { _ in session.onConfigChanged() }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Szukaj")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if session.isRegex {
                        RegexHelperMenu { session.insertToken($0, into: \.search) }
                    }
                }
                TextField(session.isRegex ? "Wyrażenie regularne" : "Tekst do znalezienia", text: $session.search)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .controlSize(.large)
                    .accessibilityLabel("Szukaj w nazwie")
                    .onChange(of: session.search) { _ in session.onConfigChanged() }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Zamień na")
                        .foregroundStyle(.secondary)
                    Spacer()
                    VariableInsertMenu(includeGroups: session.isRegex) {
                        session.insertToken($0, into: \.replacement)
                    }
                }
                TextField("Tekst zastępujący", text: $session.replacement)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .controlSize(.large)
                    .accessibilityLabel("Tekst zastępujący")
                    .onChange(of: session.replacement) { _ in session.onConfigChanged() }
            }

            Toggle("Rozróżniaj wielkość liter", isOn: $session.caseSensitive)
                .toggleStyle(.checkbox)
                .onChange(of: session.caseSensitive) { _ in session.onConfigChanged() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
