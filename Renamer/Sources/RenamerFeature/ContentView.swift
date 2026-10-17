import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var session: RenameSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showInspector = true

    public init() {}

    public var body: some View {
        workspace
            .navigationTitle("Renamer")
            .toolbar {
                addFilesToolbarItem

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: session.undoLast) {
                        Label("Cofnij zmianę nazw", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!session.canUndo)
                    .help("Cofnij ostatnią zmianę nazw")

                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Reguły zmiany nazw", systemImage: "sidebar.right")
                    }
                    .help(showInspector ? "Ukryj reguły" : "Pokaż reguły")
                }

                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: session.requestApply) {
                        Label("Zmień nazwy", systemImage: "checkmark")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
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
                Text("Liczba plików do nadpisania: \(session.warningCount). Kontynuować?")
            }
    }

    @ToolbarContentBuilder
    private var addFilesToolbarItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                AddFilesButton()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                AddFilesButton()
            }
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
