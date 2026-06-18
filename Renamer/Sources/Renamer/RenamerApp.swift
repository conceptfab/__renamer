import SwiftUI

@main
struct RenamerApp: App {
    @StateObject private var session = RenameSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 860, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
