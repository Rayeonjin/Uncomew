import SwiftUI

@main
struct UncomewApp: App {
    @StateObject private var analyzer = StorageAnalyzer()
    @StateObject private var uninstaller = AppUninstaller()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(analyzer)
                .environmentObject(uninstaller)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1040, height: 720)

        Settings {
            SettingsView()
                .environmentObject(analyzer)
        }
    }
}
