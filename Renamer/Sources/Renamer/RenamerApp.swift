import SwiftUI

@main
struct RenamerApp: App {
    @StateObject private var session = RenameSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 1120, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1160, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
