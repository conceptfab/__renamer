import AppKit

/// Presents the standard "open files" panel and feeds the chosen URLs to the
/// session. Shared by the drop zone and the toolbar "add files" button.
@MainActor
func presentOpenFilesPanel(into session: RenameSession) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.begin { response in
        guard response == .OK else { return }
        session.addURLs(panel.urls)
    }
}
