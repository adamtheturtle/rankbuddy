//
//  DetailWindow.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// Identifies an item to show in its own window (#49). `Codable` + `Hashable` so it can pass
/// through `openWindow(value:)` and be restored by the `WindowGroup`.
nonisolated enum DetailWindowValue: Codable, Hashable {
    case test(Test)
    case candidate(TestCandidate)
    case question(Question)
    case interview(Interview)

    /// The standalone window's title.
    var windowTitle: String {
        switch self {
        case let .test(test): test.name
        case let .candidate(candidate): candidate.fullName ?? candidate.email
        case let .question(question): question.name
        case let .interview(interview): interview.title ?? "Interview \(interview.id)"
        }
    }
}

/// Renders the detail for a `DetailWindowValue` in a standalone window (#49).
struct DetailWindowContent: View {
    let value: DetailWindowValue?
    @Environment(AccountStore.self) private var store

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(value?.windowTitle ?? "RankBuddy")
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder private var content: some View {
        switch value {
        case let .test(test):
            if let account = store.currentAccount {
                TestDetailView(test: test, account: account)
            } else {
                NoAccountView()
            }

        case let .candidate(candidate):
            CandidateDetailView(candidate: candidate)

        case let .question(question):
            QuestionDetailView(question: question)

        case let .interview(interview):
            InterviewDetailView(interview: interview)

        case nil:
            ContentUnavailableView("Nothing to show", systemImage: "questionmark")
        }
    }
}
