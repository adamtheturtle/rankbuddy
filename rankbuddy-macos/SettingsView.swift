import SwiftUI

/// The app's Settings scene.
///
/// Account management — adding a HackerRank account, entering and validating a
/// token — lands in #2; for now this is a navigable placeholder so the Settings
/// window opens reliably.
struct SettingsView: View {
    var body: some View {
        TabView {
            Form {
                Section("Accounts") {
                    Text("Account management is coming soon.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Accounts", systemImage: "person.crop.circle")
            }
        }
        .frame(width: 480, height: 320)
    }
}

#Preview {
    SettingsView()
}
