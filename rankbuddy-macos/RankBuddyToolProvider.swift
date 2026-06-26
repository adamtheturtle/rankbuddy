import BuddyAppKit
import BuddyMCP
import Foundation
import MCP

/// The RankBuddy MCP tool catalogue (#9): read-only, account-aware tools over the HackerRank
/// for Work data, served via buddy-kit's `BuddyMCPServer`.
///
/// Read-only by default — no write/create tools (those would need an explicit, separately
/// reviewed opt-in). Every tool resolves a target account (an `account` argument matching a
/// label or id, else the current account) and dispatches through the same `HackerRankClient`
/// the app uses, so the mock account works in tests without live credentials.
nonisolated struct RankBuddyToolProvider: MCPToolProvider {
    /// How the provider obtains the account store; injectable so tests use a seeded mock store
    /// instead of the real keychain.
    private let makeStore: @Sendable @MainActor () -> AccountStore

    init(makeStore: @escaping @Sendable @MainActor () -> AccountStore = { AccountStore.rankBuddy() }) {
        self.makeStore = makeStore
    }

    func tools() async -> [Tool] {
        mcpTools(from: Self.descriptors)
    }

    func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        let account = stringArgument(arguments, "account")
        switch name {
        case "list_accounts":
            return await listAccounts()

        case "list_tests":
            return await listTests(account: account)

        case "list_questions":
            return await listQuestions(account: account)

        case "list_interviews":
            return await listInterviews(account: account)

        case "list_candidates":
            guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }

            return await listCandidates(testID: testID, account: account)

        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    // MARK: - Account resolution

    /// The account matching `identifier` (label or id), or the current account when nil/unknown.
    @MainActor
    private func resolveAccount(_ identifier: String?) -> Account? {
        let store = makeStore()
        guard let identifier else { return store.currentAccount }

        return store.accounts.first { $0.label == identifier || $0.id.uuidString == identifier }
            ?? store.currentAccount
    }

    // MARK: - Tools

    @MainActor
    private func listAccounts() -> CallTool.Result {
        let store = makeStore()
        let accounts = store.accounts.map { account in
            ["id": account.id.uuidString, "label": account.label, "current": account.id == store.currentAccountID]
        }
        return jsonResult(["accounts": accounts, "count": accounts.count])
    }

    @MainActor
    private func listTests(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).testsPage()
            let items = page.items.map { ["id": $0.id, "name": $0.name, "state": $0.state ?? ""] }
            return jsonResult([
                "account": resolved.label,
                "tests": items,
                "count": items.count,
                "has_more": page.next != nil
            ])
        } catch {
            return errorResult("Couldn't list tests: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listQuestions(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).questionsPage()
            let items = page.items.map { ["id": $0.id, "name": $0.name, "type": $0.type] }
            return jsonResult([
                "account": resolved.label,
                "questions": items,
                "count": items.count,
                "has_more": page.next != nil
            ])
        } catch {
            return errorResult("Couldn't list questions: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listInterviews(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).interviewsPage()
            let items = page.items.map { ["id": $0.id, "title": $0.title ?? "", "status": $0.status] }
            return jsonResult([
                "account": resolved.label,
                "interviews": items,
                "count": items.count,
                "has_more": page.next != nil
            ])
        } catch {
            return errorResult("Couldn't list interviews: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listCandidates(testID: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).candidatesPage(testID: testID)
            let items = page.items.map { candidate in
                [
                    "id": candidate.id,
                    "email": candidate.email,
                    "name": candidate.fullName ?? "",
                    "score": candidate.score ?? 0,
                    "status": candidate.listStatusLabel ?? ""
                ]
            }
            return jsonResult([
                "account": resolved.label,
                "test_id": testID,
                "candidates": items,
                "count": items.count,
                "has_more": page.next != nil
            ])
        } catch {
            return errorResult("Couldn't list candidates: \(error.localizedDescription)")
        }
    }

    // MARK: - Catalogue

    /// The advertised tool descriptors. All read-only (`readOnlyHint`), each taking an optional
    /// `account` (label or id).
    static let descriptors: [[String: Any]] = {
        let account: [String: Any] = [
            "type": "string",
            "description": "Account label or id; defaults to the current account."
        ]
        func readOnly(
            _ name: String,
            _ description: String,
            properties: [String: Any],
            required: [String] = []
        ) -> [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return [
                "name": name,
                "description": description,
                "annotations": ["readOnlyHint": true],
                "inputSchema": schema
            ]
        }
        return [
            readOnly("list_accounts", "List the configured RankBuddy accounts (no tokens).", properties: [:]),
            readOnly("list_tests", "List the current (or named) account's HackerRank tests (first page).",
                     properties: ["account": account]),
            readOnly("list_questions", "List the account's questions (first page).",
                     properties: ["account": account]),
            readOnly("list_interviews", "List the account's interviews (first page).",
                     properties: ["account": account]),
            readOnly("list_candidates", "List the candidates for a test.",
                     properties: ["test_id": ["type": "string", "description": "The test's id."], "account": account],
                     required: ["test_id"])
        ]
    }()
}
