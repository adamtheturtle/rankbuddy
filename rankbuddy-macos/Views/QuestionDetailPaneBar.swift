//
//  QuestionDetailPaneBar.swift
//  rankbuddy-macos
//

import SwiftUI

nonisolated enum QuestionDetailPane: String, CaseIterable, Identifiable {
    case overview
    case content
    case answer
    case coding

    var id: Self {
        self
    }

    var label: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .content: "Content"
        case .answer: "Answer"
        case .coding: "Coding"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .content: "text.alignleft"
        case .answer: "checkmark.seal"
        case .coding: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// A pinned, horizontally scrolling section switcher for question details. The visible chips
/// match PadBuddy's compact detail navigation while the accessibility representation remains
/// a native exclusive picker.
struct QuestionDetailPaneBar: View {
    let panes: [QuestionDetailPane]
    let selection: QuestionDetailPane
    let select: (QuestionDetailPane) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(panes) { pane in
                    Button {
                        select(pane)
                    } label: {
                        Label(pane.label, systemImage: pane.systemImage)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == pane ? Color.accentColor : Color.secondary)
                    .background(selection == pane ? Color.accentColor.opacity(0.14) : Color.clear)
                    .clipShape(.capsule)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityRepresentation {
            Picker("Question detail section", selection: accessibilitySelection) {
                ForEach(panes) { pane in
                    Text(pane.label).tag(pane)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var accessibilitySelection: Binding<QuestionDetailPane> {
        Binding(get: { selection }, set: { select($0) })
    }
}
