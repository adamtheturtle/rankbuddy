import AppKit
import SwiftUI

/// The contents of the menu bar extra: quick navigation to each section and common
/// actions. Selecting a section sets the persisted selection and brings the main window
/// forward (#23).
struct MenuBarContent: View {
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(SidebarSection.allCases) { section in
            Button(section.title) {
                selection = section
                showMainWindow()
            }
        }

        Divider()

        Button("Open RankBuddy") { showMainWindow() }

        Divider()

        Button("Quit RankBuddy") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: WindowID.main)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
