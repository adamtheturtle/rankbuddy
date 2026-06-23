import SwiftUI

/// The main window's root: a split view with a sidebar of the top-level
/// sections and a detail pane.
///
/// The section lists and detail views are read-only and land per section in
/// #5–#8; for now each section shows an empty state so the shell is navigable.
struct ContentView: View {
    @State private var selection: SidebarSection? = .tests

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("RankBuddy")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let selection {
                SectionPlaceholderView(section: selection)
            } else {
                ContentUnavailableView(
                    "Select a section",
                    systemImage: "sidebar.left"
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
