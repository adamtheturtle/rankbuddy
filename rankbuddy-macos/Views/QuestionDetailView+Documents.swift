//
//  QuestionDetailView+Documents.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

enum QuestionDocumentAction {
    case print
    case exportMarkdown

    var title: String {
        switch self {
        case .print: "Choose Print Audience"
        case .exportMarkdown: "Choose Export Audience"
        }
    }
}

extension QuestionDetailView {
    var documentAudiencePresented: Binding<Bool> {
        Binding(get: { documentAction != nil }, set: {
            if !$0 {
                documentAction = nil
            }
        })
    }

    @ViewBuilder var documentAudienceButtons: some View {
        if let action = documentAction {
            Button("Candidate Copy") { performDocumentAction(action, audience: .candidate) }
            Button("Interviewer Copy (Includes Confidential Content)") {
                performDocumentAction(action, audience: .interviewer)
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func performDocumentAction(_ action: QuestionDocumentAction, audience: QuestionDocumentAudience) {
        let snapshot = QuestionReportData(question: displayed, detail: detail, audience: audience)
        switch action {
        case .print:
            printReport(QuestionReport(data: snapshot), jobTitle: "Question: \(snapshot.question.name)")
        case .exportMarkdown:
            MarkdownExport.save({ MarkdownExport.question(snapshot) }, suggestedName: snapshot.question.name)
        }
    }
}
