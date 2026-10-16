import SwiftUI
import RenamerCore

struct NameFormatControls: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Nazwa", selection: $session.nameCase) {
                ForEach(CaseMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: session.nameCase) { _ in session.onConfigChanged() }

            Toggle("Chroń rozszerzenie pliku", isOn: $session.lockExtension)
                .toggleStyle(.checkbox)
                .onChange(of: session.lockExtension) { _ in session.onConfigChanged() }

            if !session.lockExtension {
                Picker("Rozszerzenie", selection: $session.extCase) {
                    ForEach(CaseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: session.extCase) { _ in session.onConfigChanged() }
            }

            Toggle("Usuń znaki diakrytyczne", isOn: $session.stripDiacritics)
                .toggleStyle(.checkbox)
                .onChange(of: session.stripDiacritics) { _ in session.onConfigChanged() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
