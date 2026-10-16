import SwiftUI

struct FindReplaceControls: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        Group {
            Picker("Tryb", selection: $session.isRegex) {
                Text("Tekst").tag(false)
                Text("Regex").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: session.isRegex) { _ in session.onConfigChanged() }

            TextField("Szukaj", text: $session.search)
                .textFieldStyle(.plain)
                .accessibilityLabel("Szukaj w nazwie")
                .onChange(of: session.search) { _ in session.onConfigChanged() }

            TextField("Zamień na", text: $session.replacement)
                .textFieldStyle(.plain)
                .accessibilityLabel("Tekst zastępujący")
                .onChange(of: session.replacement) { _ in session.onConfigChanged() }

            HStack {
                if session.isRegex {
                    RegexHelperMenu { session.insertToken($0, into: \.search) }
                } else {
                    Text("Zmienne")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VariableInsertMenu(includeGroups: session.isRegex) {
                    session.insertToken($0, into: \.replacement)
                }
            }

            Toggle("Wielkość liter ma znaczenie", isOn: $session.caseSensitive)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: session.caseSensitive) { _ in session.onConfigChanged() }
        }
    }
}
