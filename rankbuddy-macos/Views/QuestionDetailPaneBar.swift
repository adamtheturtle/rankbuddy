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
}

/// Native segmented tabs when they fit; an explicit section menu in narrower detail panes.
struct QuestionDetailPaneBar: View {
    let panes: [QuestionDetailPane]
    let selection: QuestionDetailPane
    let select: (QuestionDetailPane) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            sectionPicker.pickerStyle(.segmented).labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
            sectionPicker.pickerStyle(.menu).labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Question detail section")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var sectionPicker: some View {
        Picker("Question detail section", selection: selectionBinding) {
            ForEach(panes) { pane in
                Text(pane.label).tag(pane)
            }
        }
    }

    private var selectionBinding: Binding<QuestionDetailPane> {
        Binding(get: { selection }, set: { select($0) })
    }
}
