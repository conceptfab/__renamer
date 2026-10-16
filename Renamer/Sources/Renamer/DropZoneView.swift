import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject private var session: RenameSession
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        emptyState
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.05) : .clear)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label(isTargeted ? "Upuść pliki tutaj" : "Dodaj pliki do zmiany nazw",
                      systemImage: "doc.on.doc")
            } description: {
                Text("Przeciągnij pliki do okna lub wybierz je z dysku.")
            } actions: {
                openFilesButton
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(isTargeted ? "Upuść pliki tutaj" : "Dodaj pliki do zmiany nazw")
                    .font(.title2)
                Text("Przeciągnij pliki do okna lub wybierz je z dysku.")
                    .foregroundStyle(.secondary)
                openFilesButton
            }
        }
    }

    private var openFilesButton: some View {
        Button("Wybierz pliki…") { presentOpenFilesPanel(into: session) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let url = item as? URL {
                    resolved = url
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    resolved = url
                }
                guard let resolved else { return }
                lock.lock()
                urls.append(resolved)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            session.addURLs(urls)
        }
        return true
    }
}
