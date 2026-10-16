import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject private var session: RenameSession
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 104, height: 104)
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.blue)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(isTargeted ? "Upuść pliki tutaj" : "Zmień nazwy plików")
                    .font(.system(size: 27, weight: .semibold))
                Text("Dodaj pliki, ustaw reguły i sprawdź nowe nazwy.\nWszystko w jednym miejscu.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

            Button {
                presentOpenFilesPanel(into: session)
            } label: {
                Label("Wybierz pliki…", systemImage: "plus")
                    .padding(.horizontal, 8)
            }
            .controlSize(.large)
            .modifier(PrimaryActionStyle())

            Text("lub przeciągnij je do tego okna")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
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
