import SwiftUI

/// The main window's root: a split view with a sidebar of the top-level sections and a
/// detail pane that hosts the selected section's read-only list and detail views.
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
                detailView(for: selection)
            } else {
                ContentUnavailableView(
                    "Select a section",
                    systemImage: "sidebar.left"
                )
            }
        }
    }

    @ViewBuilder private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .tests:
            TestsScreen()
        case .questions:
            QuestionsScreen()
        case .interviews:
            InterviewsScreen()
        }
    }
}

#Preview {
    ContentView()
        .environment(AccountStore.rankBuddy(isTesting: true))
}
