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
    case candidate(testID: String, candidateID: String, accountID: UUID?)
    case question(Question, accountID: UUID?)
    case interview(Interview)
    case user(userID: String, userName: String, accountID: UUID?)
    case team(teamID: String, teamName: String, accountID: UUID?)
    case teamMembers(teamID: String, teamName: String, accountID: UUID?)
    case testCandidates(testID: String, testName: String, accountID: UUID?)

    /// The standalone window's title.
    var windowTitle: String {
        switch self {
        case let .test(test, _): test.name
        case .candidate: "Candidate"
        case let .question(question, _): question.name
        case let .interview(interview): interview.title ?? "Interview \(interview.id)"
        case let .user(_, userName, _): userName
        case let .team(_, teamName, _): teamName
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

nonisolated extension DetailWindowValue {
    static func candidateWindow(_ candidate: TestCandidate, testID: String, accountID: UUID?) -> Self {
        .candidate(testID: testID, candidateID: candidate.id, accountID: accountID)
    }

    static func userWindow(_ user: User, accountID: UUID?) -> Self {
        .user(userID: user.id, userName: user.displayName, accountID: accountID)
    }

    static func teamWindow(_ team: Team, accountID: UUID?) -> Self {
        .team(teamID: team.id, teamName: team.name, accountID: accountID)
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

        case let .candidate(testID, candidateID, accountID):
            if let account = resolvedAccount(accountID) {
                StandaloneCandidateDetailView(
                    testID: testID,
                    candidateID: candidateID,
                    account: account
                )
            } else {
                NoAccountView()
            }

        case let .question(question, accountID):
            if let account = resolvedAccount(accountID) {
                QuestionDetailView(question: question, account: account)
            } else {
                NoAccountView()
            }

        case let .interview(interview):
            InterviewDetailView(interview: interview)

        case let .user(userID, _, accountID):
            if let account = resolvedAccount(accountID) {
                StandaloneUserDetailView(userID: userID, account: account)
            } else {
                NoAccountView()
            }

        case let .team(teamID, _, accountID):
            if let account = resolvedAccount(accountID) {
                StandaloneTeamDetailView(teamID: teamID, account: account)
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

/// Fetches sensitive candidate details only after resolving the authorized account; window
/// restoration stores opaque identifiers rather than candidate PII or assessment results.
private struct StandaloneCandidateDetailView: View {
    let testID: String
    let candidateID: String
    let account: Account

    @State private var candidate: TestCandidate?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let candidate {
                CandidateDetailView(candidate: candidate, testID: testID, account: account) {
                    Task { await load() }
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Candidate", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView("Loading candidate…")
            }
        }
        .task(id: candidateID) { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            candidate = try await HackerRankClient(account: account).candidate(
                testID: testID,
                candidateID: candidateID
            )
        } catch {
            guard !Task.isCancelled else { return }

            candidate = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Reloads a standalone organisation user from its persisted identity so role, status, and
/// permissions reflect HackerRank when a window is opened or restored.
private struct StandaloneUserDetailView: View {
    let userID: String
    let account: Account

    @State private var user: User?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let user {
                PersonDetailView(user: user, account: account) {
                    Task { await load() }
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load User", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView("Loading user…")
            }
        }
        .task(id: userID) { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            user = try await HackerRankClient(account: account).user(id: userID)
        } catch {
            guard !Task.isCancelled else { return }

            user = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Reloads a standalone team from its persisted identity so restored windows never present a
/// serialized list-row snapshot as current server state.
private struct StandaloneTeamDetailView: View {
    let teamID: String
    let account: Account

    @State private var team: Team?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let team {
                TeamDetailView(team: team, account: account) {
                    Task { await load() }
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Team", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView("Loading team…")
            }
        }
        .task(id: teamID) { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            team = try await HackerRankClient(account: account).team(id: teamID)
        } catch {
            guard !Task.isCancelled else { return }

            team = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
