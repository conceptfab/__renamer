import SwiftUI
import RenamerCore

struct ControlsPanel: View {
    @EnvironmentObject private var session: RenameSession
    @State private var showNameDialog = false
    @State private var nameDialogText = ""
    @State private var isRenamingPreset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                Text("Reguły zmiany nazw")
                    .font(.headline)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 4)

            Form {
                Section {
                    presetControls
                } header: {
                    Text("Schemat")
                }

                Section {
                    TemplateControls()
                } header: {
                    Text("Nowa nazwa")
                } footer: {
                    Text("Pozostaw puste, aby edytować obecną nazwę.")
                }

                Section("Znajdź i zamień") {
                    FindReplaceControls()
                }

                Section("Formatowanie") {
                    NameFormatControls()
                }
            }
            .formStyle(.grouped)
            .controlSize(.large)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(isRenamingPreset ? "Zmień nazwę schematu" : "Zapisz schemat",
               isPresented: $showNameDialog) {
            TextField("Nazwa schematu", text: $nameDialogText)
            Button("Anuluj", role: .cancel) {}
            Button("Zapisz", action: savePreset)
                .disabled(nameDialogText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var presetControls: some View {
        HStack(spacing: 10) {
            Menu {
                if session.presets.isEmpty {
                    Text("Brak zapisanych schematów").disabled(true)
                }
                ForEach(session.presets) { preset in
                    Button(preset.name) { session.applyPreset(preset) }
                }
                Divider()
                Button("Zapisz bieżące ustawienia…", action: beginSavingPreset)
            } label: {
                Text(selectedPreset?.name ?? "Własne ustawienia")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Schemat zmiany nazw")

            Menu {
                Button("Zapisz jako nowy schemat…", action: beginSavingPreset)
                Button("Zmień nazwę schematu…", action: beginRenamingPreset)
                    .disabled(selectedPreset == nil)
                Divider()
                Button("Usuń schemat", role: .destructive) {
                    if let id = session.selectedPresetID { session.deletePreset(id: id) }
                }
                .disabled(selectedPreset == nil)
            } label: {
                Label("Zarządzaj schematami", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Zapisz lub edytuj schemat")
        }
    }

    private var selectedPreset: Preset? {
        session.presets.first { $0.id == session.selectedPresetID }
    }

    private func beginSavingPreset() {
        isRenamingPreset = false
        nameDialogText = ""
        showNameDialog = true
    }

    private func beginRenamingPreset() {
        isRenamingPreset = true
        nameDialogText = selectedPreset?.name ?? ""
        showNameDialog = true
    }

    private func savePreset() {
        if isRenamingPreset, let id = session.selectedPresetID {
            session.renamePreset(id: id, to: nameDialogText)
        } else {
            session.saveCurrentAsPreset(name: nameDialogText)
        }
    }
}
