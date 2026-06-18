import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var session: RenameSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if session.items.isEmpty {
                DropZoneView()
            } else {
                ControlsPanel()
                Divider()
                PreviewTable()
            }
            Divider()
            FooterBar()
        }
        .overlay(alignment: .top) {
            if let banner = session.successBanner {
                ResultBanner(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.successBanner)
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

    private func openMoreFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            session.addURLs(panel.urls)
        }
    }

    private var header: some View {
        HStack {
            Text("Zmień nazwy")
                .font(.title2.weight(.semibold))
            Spacer()
            if !session.items.isEmpty {
                Text("\(session.items.count) plików · \(session.errorCount + session.warningCount) problemów")
                    .foregroundStyle(.secondary)
                Button("Dodaj pliki…") { openMoreFiles() }
                Button("Wyczyść listę") { session.removeAll() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
