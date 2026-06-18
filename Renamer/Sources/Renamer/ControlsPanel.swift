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
                TokenInsertMenu()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Szukaj")
                    .frame(width: 90, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("", text: $session.search)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: session.search) { _ in session.onConfigChanged() }
                Text("Zamień")
                    .foregroundStyle(.secondary)
                TextField("", text: $session.replacement)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: session.replacement) { _ in session.onConfigChanged() }
            }

            HStack(spacing: 16) {
                Toggle("Wyrażenie regularne", isOn: $session.isRegex)
                    .onChange(of: session.isRegex) { _ in session.onConfigChanged() }
                Toggle("Rozróżniaj wielkość", isOn: $session.caseSensitive)
                    .onChange(of: session.caseSensitive) { _ in session.onConfigChanged() }
                Toggle("Usuń diakrytyki", isOn: $session.stripDiacritics)
                    .onChange(of: session.stripDiacritics) { _ in session.onConfigChanged() }
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
                    .foregroundStyle(.secondary)
                Picker("Rozszerzenie", selection: $session.extCase) {
                    ForEach(CaseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: session.extCase) { _ in session.onConfigChanged() }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct TokenInsertMenu: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        Menu {
            Button("{name}") { session.insertToken("{name}") }
            Button("{ext}") { session.insertToken("{ext}") }
            Button("{parent}") { session.insertToken("{parent}") }
            Button("{counter:001}") { session.insertToken("{counter:001}") }
            Button("{date}") { session.insertToken("{date}") }
            Button("{time}") { session.insertToken("{time}") }
        } label: {
            Label("Wstaw", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
