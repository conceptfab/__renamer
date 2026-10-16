import SwiftUI
import RenamerCore

struct NameFormatControls: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        Group {
            Picker("Wielkość liter", selection: $session.nameCase) {
                ForEach(CaseMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .onChange(of: session.nameCase) { _ in session.onConfigChanged() }

            Toggle("Chroń rozszerzenie", isOn: $session.lockExtension)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: session.lockExtension) { _ in session.onConfigChanged() }

            if !session.lockExtension {
                Picker("Rozszerzenie", selection: $session.extCase) {
                    ForEach(CaseMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .onChange(of: session.extCase) { _ in session.onConfigChanged() }
            }

            Toggle("Usuń znaki diakrytyczne", isOn: $session.stripDiacritics)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: session.stripDiacritics) { _ in session.onConfigChanged() }
        }
    }
}
