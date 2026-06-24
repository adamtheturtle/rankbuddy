import AppKit
import SwiftUI

/// Shared state for the command palette, toggled from the menu/keyboard and observed by
/// `ContentView`, which presents the palette sheet.
@Observable
@MainActor
final class PaletteModel {
    var isPresented = false
}

/// A command the palette can run: jump to a section or open another app destination.
enum PaletteCommand: Identifiable, Hashable {
    case section(SidebarSection)
    case openSettings

    /// Every command, in the order they appear before any query narrows them.
    static var all: [Self] {
        SidebarSection.allCases.map(section) + [.openSettings]
    }

    var id: String {
        switch self {
        case let .section(section): "section.\(section.id)"
        case .openSettings: "command.settings"
        }
    }

    var title: String {
        switch self {
        case let .section(section): section.title
        case .openSettings: "Open Settings"
        }
    }

    var systemImage: String {
        switch self {
        case let .section(section): section.systemImage
        case .openSettings: "gearshape"
        }
    }

    /// Commands whose title matches `query`, ranked by a deterministic fuzzy score.
    ///
    /// Ties keep the declared order, so the ranking — and therefore the highlighted
    /// result — stays stable as the query changes.
    static func ranked(matching query: String) -> [Self] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }

        var scored: [ScoredCommand] = []
        for (order, command) in all.enumerated() {
            guard let score = FuzzyMatch.score(query: trimmed, in: command.title) else { continue }

            scored.append(ScoredCommand(order: order, command: command, score: score))
        }

        // Higher score first; ties keep the declared order so the highlight stays stable.
        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.order < rhs.order : lhs.score > rhs.score
        }
        return scored.map(\.command)
    }
}

/// A palette command paired with its fuzzy score and declared order, used while ranking.
private struct ScoredCommand {
    let order: Int
    let command: PaletteCommand
    let score: Int
}

/// A small deterministic fuzzy matcher for ranking command-palette results.
enum FuzzyMatch {
    /// Returns a match score for `query` as a subsequence of `candidate`, or `nil` when
    /// `candidate` doesn't contain the query's characters in order. Higher is better:
    /// consecutive characters and word-start matches score more.
    static func score(query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased())
        let haystack = Array(candidate.lowercased())
        guard !needle.isEmpty else { return 0 }

        var score = 0
        var needleIndex = 0
        var previousMatch = -2
        for (position, character) in haystack.enumerated() where needleIndex < needle.count {
            guard character == needle[needleIndex] else { continue }

            score += 1
            if position == previousMatch + 1 { score += 2 } // consecutive-run bonus
            if position == 0 || haystack[position - 1] == " " { score += 3 } // word-start bonus
            previousMatch = position
            needleIndex += 1
        }
        return needleIndex == needle.count ? score : nil
    }
}

/// A command palette (⌘K) for jumping between sections and other app destinations,
/// with fuzzy ranking and full keyboard navigation (↑/↓ to move, Return to run, Escape
/// to dismiss).
struct CommandPaletteView: View {
    @Binding var selection: SidebarSection
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlighted: PaletteCommand.ID?
    @FocusState private var fieldFocused: Bool

    private var matches: [PaletteCommand] {
        PaletteCommand.ranked(matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search commands…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($fieldFocused)
                .onKeyPress(.upArrow) { move(by: -1); return .handled }
                .onKeyPress(.downArrow) { move(by: 1); return .handled }
                .onKeyPress(.return) { run(highlightedCommand); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }

            Divider()

            List(matches, selection: $highlighted) { command in
                Button {
                    run(command)
                } label: {
                    Label(command.title, systemImage: command.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tag(command.id)
            }
        }
        .frame(width: 440, height: 320)
        .onAppear {
            fieldFocused = true
            highlighted = matches.first?.id
        }
        .onChange(of: query) {
            // Keep a stable, valid highlight as the result set narrows.
            if highlighted == nil || !matches.contains(where: { $0.id == highlighted }) {
                highlighted = matches.first?.id
            }
        }
    }

    /// The command the highlight currently points at, falling back to the top match.
    private var highlightedCommand: PaletteCommand? {
        matches.first { $0.id == highlighted } ?? matches.first
    }

    /// Moves the highlight by `delta` rows, wrapping around the ends.
    private func move(by delta: Int) {
        guard !matches.isEmpty else { return }

        let index = matches.firstIndex { $0.id == highlighted } ?? 0
        let next = (index + delta + matches.count) % matches.count
        highlighted = matches[next].id
    }

    private func run(_ command: PaletteCommand?) {
        guard let command else { return }

        switch command {
        case let .section(section):
            selection = section
            dismiss()

        case .openSettings:
            dismiss()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
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
