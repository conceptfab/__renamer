import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var session: RenameSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("renamer.appearance") private var appearance: AppAppearance = .light
    @State private var showInspector = true

    var body: some View {
        workspace
            .navigationTitle("Renamer")
            .preferredColorScheme(appearance.colorScheme)
            .tint(.blue)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        presentOpenFilesPanel(into: session)
                    } label: {
                        Label("Dodaj pliki", systemImage: "plus")
                    }
                    .labelStyle(.titleAndIcon)
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Dodaj pliki (⌘O)")
                }

                ToolbarItemGroup(placement: .automatic) {
                    Button(action: session.undoLast) {
                        Label("Cofnij zmianę nazw", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!session.canUndo)
                    .help("Cofnij ostatnią zmianę nazw")

                    Menu {
                        Picker("Wygląd", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label("Wygląd", systemImage: "circle.lefthalf.filled")
                    }
                    .help("Wygląd aplikacji")

                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Reguły zmiany nazw", systemImage: "sidebar.right")
                    }
                    .help(showInspector ? "Ukryj reguły" : "Pokaż reguły")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: session.requestApply) {
                        Label("Zmień nazwy", systemImage: "checkmark")
                    }
                    .labelStyle(.titleAndIcon)
                    .modifier(PrimaryActionStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!session.canApply)
                }
            }
            .overlay(alignment: .top) {
                if let banner = session.successBanner {
                    ResultBanner(banner: banner)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: session.successBanner)
            .sheet(item: $session.failureReport) { report in
                FailureReportSheet(report: report)
            }
            .alert("Nadpisać istniejące pliki?", isPresented: $session.showOverwriteAlert) {
                Button("Anuluj", role: .cancel) {}
                Button("Kontynuuj", role: .destructive) {
                    session.apply(overwrite: true)
                }
            } message: {
                Text("\(session.warningCount) plik(ów) zostanie nadpisanych. Kontynuować?")
            }
    }

    @ViewBuilder
    private var workspace: some View {
        if #available(macOS 14.0, *) {
            RenameWorkspace()
                .inspector(isPresented: $showInspector) {
                    ControlsPanel()
                        .inspectorColumnWidth(min: 320, ideal: 344, max: 400)
                }
        } else {
            HStack(spacing: 0) {
                RenameWorkspace()
                if showInspector {
                    Divider()
                    ControlsPanel()
                        .frame(width: 344)
                }
            }
        }
    }
}
