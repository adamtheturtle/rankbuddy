import SwiftUI

/// A temporary empty-state shown for a section until its read-only list and
/// detail views land (#5–#8).
struct SectionPlaceholderView: View {
    let section: SidebarSection

    var body: some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.systemImage)
        } description: {
            Text("\(section.title) will appear here once an account is connected.")
        }
        .navigationTitle(section.title)
    }
}

#Preview {
    SectionPlaceholderView(section: .tests)
}
