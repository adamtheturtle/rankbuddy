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
    case question(Question, accountID: UUID?)
    case interview(Interview)
    case user(User, accountID: UUID?)
    case team(Team, accountID: UUID?)
    case teamMembers(teamID: String, teamName: String, accountID: UUID?)
    case testCandidates(testID: String, testName: String, accountID: UUID?)

    /// The standalone window's title.
    var windowTitle: String {
        switch self {
        case let .test(test, _): test.name
        case let .candidate(candidate): candidate.fullName ?? candidate.email
        case let .question(question, _): question.name
        case let .interview(interview): interview.title ?? "Interview \(interview.id)"
        case let .user(user, _): user.displayName
        case let .team(team, _): team.name
        case let .teamMembers(_, teamName, _): "\(teamName) Members"
        case let .testCandidates(_, testName, _): "\(testName) Candidates"
        }
    }

    /// Whether the value shows a full `LoadableList` rather than a detail form.
    var isStandaloneList: Bool {
        switch self {
        case .teamMembers, .testCandidates: true
        default: false
        }
    }
}

nonisolated enum DetailWindowAccountResolution {
    static func resolve(id: UUID?, accounts: [Account], current: Account?) -> Account? {
        guard let id else { return current }

        return accounts.first { $0.id == id }
    }
}

/// Renders the detail for a `DetailWindowValue` in a standalone window (#49).
struct DetailWindowContent: View {
    let value: DetailWindowValue?
    @Environment(AccountStore.self) private var store

    var body: some View {
        Group {
            // A standalone list is a full `LoadableList`, which brings its own navigation
            // containers (split panes, search, toolbar) — wrapping it in another stack nests
            // them, which is what wedged the in-pane pushes these windows replaced.
            if value?.isStandaloneList == true {
                content
            } else {
                NavigationStack {
                    content
                        .navigationTitle(value?.windowTitle ?? "RankBuddy")
                }
            }
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

        case let .question(question, accountID):
            if let account = resolvedAccount(accountID) {
                QuestionDetailView(question: question, account: account)
            } else {
                NoAccountView()
            }

        case let .interview(interview):
            InterviewDetailView(interview: interview)

        case let .user(user, accountID):
            PersonDetailView(user: user, account: resolvedAccount(accountID))

        case let .team(team, accountID):
            if let account = resolvedAccount(accountID) {
                TeamDetailView(team: team, account: account)
            } else {
                NoAccountView()
            }

        case let .teamMembers(teamID, _, accountID):
            if let account = resolvedAccount(accountID) {
                TeamMembersList(teamID: teamID, account: account)
            } else {
                NoAccountView()
            }

        case let .testCandidates(testID, _, accountID):
            if let account = resolvedAccount(accountID) {
                CandidatesList(testID: testID, account: account)
            } else {
                NoAccountView()
            }

        case nil:
            ContentUnavailableView("Nothing to show", systemImage: "questionmark")
        }
    }

    /// The account a detail should target: the named originating account (merged rows, #17),
    /// or the current account only when the value never carried an explicit account.
    private func resolvedAccount(_ id: UUID?) -> Account? {
        DetailWindowAccountResolution.resolve(id: id, accounts: store.accounts, current: store.currentAccount)
    }
}
