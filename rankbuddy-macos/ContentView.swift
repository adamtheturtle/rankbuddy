import SwiftUI

/// The main window's root: a split view with a sidebar of the top-level sections and a
/// detail pane that hosts the selected section's read-only list and detail views.
struct ContentView: View {
    /// The selected section, persisted across launches (#19).
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: sectionSelection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("RankBuddy")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView(for: selection)
        }
    }

    /// A `List` selection binding that never clears to nil, so a section is always shown.
    private var sectionSelection: Binding<SidebarSection?> {
        Binding(
            get: { selection },
            set: { selection = $0 ?? selection }
        )
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
