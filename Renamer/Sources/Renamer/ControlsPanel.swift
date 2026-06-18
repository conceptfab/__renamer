import SwiftUI
import RenamerCore

struct ControlsPanel: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nowa nazwa")
                    .frame(width: 90, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("np. photo_{counter:001}.{ext}", text: $session.template)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: session.template) { _ in session.onConfigChanged() }
                VariableInsertMenu(includeGroups: false) { session.insertToken($0, into: \.template) }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Szukaj")
                        .frame(width: 90, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("", text: $session.search)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: session.search) { _ in session.onConfigChanged() }
                    if session.isRegex {
                        RegexHelperMenu { session.insertToken($0, into: \.search) }
                    }
                    Text("Zamień")
                        .foregroundStyle(.secondary)
                    TextField("", text: $session.replacement)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: session.replacement) { _ in session.onConfigChanged() }
                    VariableInsertMenu(includeGroups: session.isRegex) { session.insertToken($0, into: \.replacement) }
                }
                if session.isRegex {
                    Text(". dowolny znak · .* dowolny ciąg · \\d cyfra · (…) grupa · ^ początek · $ koniec")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 98)
                }
            }

            HStack(spacing: 16) {
                Picker("Tryb", selection: $session.isRegex) {
                    Text("Zwykły tekst").tag(false)
                    Text("Regex").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: session.isRegex) { _ in session.onConfigChanged() }
                Toggle("Rozróżniaj wielkość", isOn: $session.caseSensitive)
                    .onChange(of: session.caseSensitive) { _ in session.onConfigChanged() }
                Toggle("Usuń diakrytyki", isOn: $session.stripDiacritics)
                    .onChange(of: session.stripDiacritics) { _ in session.onConfigChanged() }
                Toggle("Chroń rozszerzenie pliku", isOn: $session.lockExtension)
                    .onChange(of: session.lockExtension) { _ in session.onConfigChanged() }
            }

            HStack(spacing: 12) {
                Text("Wielkość")
                    .foregroundStyle(.secondary)
                Picker("Nazwa", selection: $session.nameCase) {
                    ForEach(CaseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: session.nameCase) { _ in session.onConfigChanged() }

                Text("Rozszerzenie")
                    .foregroundStyle(session.lockExtension ? .tertiary : .secondary)
                Picker("Rozszerzenie", selection: $session.extCase) {
                    ForEach(CaseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .disabled(session.lockExtension)
                .onChange(of: session.extCase) { _ in session.onConfigChanged() }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
