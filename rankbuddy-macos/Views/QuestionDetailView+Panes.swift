//
//  QuestionDetailView+Panes.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

extension QuestionDetailView {
    @ViewBuilder var selectedPaneContent: some View {
        switch selectedPane {
        case .overview:
            QuestionDetailSection("Properties") {
                OptionalRow("Unique ID", displayed.uniqueID)
                OptionalRow("Created", DisplayFormat.date(displayed.createdAt))
                if canEdit {
                    editableRows
                } else {
                    OptionalRow("Max score", displayed.maxScore.map { $0.formatted() })
                    OptionalRow("Recommended duration", displayed.recommendedDuration.map { "\($0) minutes" })
                    OptionalRow("Languages", DisplayFormat.languages(displayed.languages))
                    OptionalRow("Skills", DisplayFormat.list(displayed.skills))
                }
            }

            if !canEdit, let tags = displayed.tags, !tags.isEmpty {
                QuestionDetailSection("Tags") {
                    TagList(tags: tags)
                }
            }

        case .content:
            problemStatementSection
            if displayed.type == "fullstack" {
                systemPromptSection
            }

        case .guidelines:
            if let notes = detail?.internalNotes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                QuestionDetailSection("Interviewer Guidelines") {
                    HTMLText(html: notes)
                }
            } else {
                ContentUnavailableView(
                    "No Interviewer Guidelines Available",
                    systemImage: "person.text.rectangle",
                    description: Text("HackerRank did not return interviewer guidelines for this question.")
                )
                .frame(maxWidth: .infinity)
            }

        case .answer:
            if let detail, !detail.options.isEmpty {
                QuestionDetailSection("Options") {
                    ForEach(Array(detail.options.enumerated()), id: \.offset) { index, option in
                        let optionText = MarkdownExport.plainText(fromHTML: option)
                        Label {
                            HTMLText(html: option)
                        } icon: {
                            Image(systemName: isCorrect(option) ? "checkmark.circle.fill" : "circle")
                        }
                        .foregroundStyle(isCorrect(option) ? Color.green : Color.primary)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityLabel(isCorrect(option) ? "\(optionText), correct answer" : optionText)
                        .id(index)
                    }
                }
            }

            if let answerText = QuestionReportData.correctAnswerText(
                from: detail?.answer,
                options: detail?.options ?? []
            ), !answerText.isEmpty {
                QuestionDetailSection("Answer") {
                    if answerRevealed {
                        Text(answerText).textSelection(.enabled)
                    } else {
                        Button {
                            answerRevealed = true
                        } label: {
                            Label("Reveal answer", systemImage: "eye")
                        }
                        .help("Show the correct answer")
                    }
                }
            }

            if detail?.options.isEmpty != false,
               QuestionReportData.correctAnswerText(from: detail?.answer, options: detail?.options ?? []) == nil {
                ContentUnavailableView(
                    "No Answer Available",
                    systemImage: "checkmark.seal",
                    description: Text("HackerRank did not return answer details for this question.")
                )
                .frame(maxWidth: .infinity)
            }

        case .coding:
            codingSection
        }
    }

    private var systemPromptSection: some View {
        QuestionDetailSection("AI system prompt", footer: """
        Customize the project AI assistant. Up to 15,000 characters. \
        Clear the text to remove the custom prompt.
        """) {
            if canEdit {
                InlineEditableText(
                    text: displayed.customSystemPrompt ?? "",
                    placeholder: "No custom system prompt",
                    preservesWhitespace: true
                ) { newValue in
                    if let issue = QuestionEditValidation.systemPromptIssue(newValue) {
                        editError = issue
                        return false
                    }
                    return await save(QuestionWriteOptions(customSystemPrompt: newValue))
                }
            } else if let prompt = displayed.customSystemPrompt, !prompt.isEmpty {
                Text(prompt).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var problemStatementSection: some View {
        if canEdit {
            QuestionDetailSection("Problem statement") {
                // Edits work on the raw source; display renders HackerRank's HTML.
                InlineEditableText(
                    text: problemStatement ?? "",
                    placeholder: "Add a problem statement",
                    rendersHTML: true
                ) { newValue in
                    await save(QuestionWriteOptions(problemStatement: newValue))
                }
            }
        } else if let statement = problemStatement {
            QuestionDetailSection("Problem statement") {
                HighlightedHTMLText(html: statement)
            }
        } else {
            ContentUnavailableView(
                "No Content Available",
                systemImage: "text.alignleft",
                description: Text("This question does not have a problem statement.")
            )
        }
    }
}

/// Unboxed detail sections share PadBuddy's heading, content spacing and readable full width.
struct QuestionDetailSection<Content: View>: View {
    let title: LocalizedStringKey
    let footer: LocalizedStringKey?
    let content: Content

    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
