import SwiftUI

/// Shared state for the command palette, toggled from the menu/keyboard and observed by
/// `ContentView`, which presents the palette sheet.
@Observable
@MainActor
final class PaletteModel {
    var isPresented = false
}

/// A lightweight command palette (⌘K) for jumping between sections.
struct CommandPaletteView: View {
    @Binding var selection: SidebarSection
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var matches: [SidebarSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SidebarSection.allCases }

        return SidebarSection.allCases.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Jump to…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($fieldFocused)
                .onSubmit { choose(matches.first) }

            Divider()

            List(matches) { section in
                Button {
                    choose(section)
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 440, height: 320)
        .onAppear { fieldFocused = true }
    }

    private func choose(_ section: SidebarSection?) {
        guard let section else { return }

        selection = section
        dismiss()
    }
}

/// App menu commands: jump to a section (⌘1/⌘2/⌘3) and open the command palette (⌘K).
struct AppCommands: Commands {
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    let palette: PaletteModel

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { selection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }

            Divider()

            Button("Command Palette…") { palette.isPresented = true }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
