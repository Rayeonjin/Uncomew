import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer

    var body: some View {
        Form {
            Section("Permissions") {
                Text("For complete results, grant Uncomew Full Disk Access in System Settings.")
                Button("Open Full Disk Access Settings") { analyzer.openPrivacySettings() }
            }
            Section("Safety") {
                Text("Storage analysis never deletes or modifies files. App Uninstaller only moves items you explicitly select to the macOS Trash, after a confirmation step.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 260)
        .padding()
    }
}
