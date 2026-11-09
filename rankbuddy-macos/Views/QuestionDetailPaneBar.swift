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
        case .guidelines: "list.bullet.rectangle"
        case .answer: "checkmark.seal"
        case .coding: "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// PadBuddy-style section chips stay pinned and scroll horizontally in narrow detail panes.
struct QuestionDetailPaneBar: View {
    let panes: [QuestionDetailPane]
    let selection: QuestionDetailPane
    let select: (QuestionDetailPane) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(panes) { pane in
                        sectionChip(pane).id(pane)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .onChange(of: selection, initial: true) { _, pane in
                proxy.scrollTo(pane, anchor: .center)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        // Preserve native exclusive selection and keyboard navigation for assistive technology.
        .accessibilityRepresentation {
            Picker("Question detail section", selection: selectionBinding) {
                ForEach(panes) { pane in
                    Text(pane.label).tag(pane)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private func sectionChip(_ pane: QuestionDetailPane) -> some View {
        let isSelected = selection == pane
        let chip = Button {
            select(pane)
        } label: {
            Label {
                Text(pane.label).lineLimit(1)
            } icon: {
                Image(systemName: pane.systemImage).accessibilityHidden(true)
            }
            .font(.callout.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(pane.label)
        .accessibilityLabel(pane.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if #available(macOS 26.0, *) {
            chip.glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.24)) : .regular.interactive(),
                             in: .rect(cornerRadius: 12))
        } else {
            chip.background(isSelected ? Color.accentColor : Color.primary.opacity(0.06),
                            in: .rect(cornerRadius: 12))
        }
    }

    private var selectionBinding: Binding<QuestionDetailPane> {
        Binding(get: { selection }, set: { select($0) })
    }
}
