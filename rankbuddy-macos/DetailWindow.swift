//
//  DetailWindow.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// Identifies an item to show in its own window (#49). `Codable` + `Hashable` so it can pass
/// through `openWindow(value:)` and be restored by the `WindowGroup`.
///
/// Details that need the owning account (`test`, `team`) carry its **id**, never the `Account`
/// itself — encoding an account here would write its token into window-restoration state. The id
/// names the originating account for merged-list rows (#17); `nil` falls back to the current
/// account (single-account context).
nonisolated enum DetailWindowValue: Codable, Hashable {
    case test(Test, accountID: UUID?)
    case candidate(TestCandidate)
    case question(Question)
    case interview(Interview)
    case user(User)
    case team(Team, accountID: UUID?)

    /// The standalone window's title.
    var windowTitle: String {
        switch self {
        case let .test(test, _): test.name
        case let .candidate(candidate): candidate.fullName ?? candidate.email
        case let .question(question): question.name
        case let .interview(interview): interview.title ?? "Interview \(interview.id)"
        case let .user(user): user.displayName
        case let .team(team, _): team.name
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
        case let .test(test, accountID):
            if let account = resolvedAccount(accountID) {
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

        case let .user(user):
            PersonDetailView(user: user)

        case let .team(team, accountID):
            if let account = resolvedAccount(accountID) {
                TeamDetailView(team: team, account: account)
            } else {
                NoAccountView()
            }

        case nil:
            ContentUnavailableView("Nothing to show", systemImage: "questionmark")
        }
    }

    /// The account a detail should target: the named originating account (merged rows, #17),
    /// or the current account when the value carries none or that account was since removed.
    private func resolvedAccount(_ id: UUID?) -> Account? {
        id.flatMap { id in store.accounts.first { $0.id == id } } ?? store.currentAccount
    }
}
