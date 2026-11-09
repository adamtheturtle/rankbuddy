//
//  QuestionDetailPaneBar.swift
//  rankbuddy-macos
//

import SwiftUI

nonisolated enum QuestionDetailPane: String, CaseIterable, Identifiable {
    case overview
    case content
    case guidelines
    case answer
    case coding

    var id: Self {
        self
    }

    var label: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .content: "Content"
        case .guidelines: "Interviewer Guidelines"
        case .answer: "Answer"
        case .coding: "Coding"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .content: "text.alignleft"
        case .guidelines: "person.text.rectangle"
        case .answer: "checkmark.seal"
        case .coding: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Full labelled tabs when they fit; an explicit section menu in narrower detail panes.
struct QuestionDetailPaneBar: View {
    let panes: [QuestionDetailPane]
    let selection: QuestionDetailPane
    let select: (QuestionDetailPane) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs.fixedSize(horizontal: true, vertical: false)
                .accessibilityRepresentation { sectionPicker.pickerStyle(.segmented) }
            sectionPicker.pickerStyle(.menu).labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Question detail section")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var tabs: some View {
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
    }

    private var sectionPicker: some View {
        Picker("Question detail section", selection: accessibilitySelection) {
            ForEach(panes) { pane in
                Label(pane.label, systemImage: pane.systemImage).tag(pane)
            }
        }
    }

    private var accessibilitySelection: Binding<QuestionDetailPane> {
        Binding(get: { selection }, set: { select($0) })
    }
}
