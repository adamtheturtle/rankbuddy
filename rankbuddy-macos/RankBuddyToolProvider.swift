//
//  RankBuddyToolProvider.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyMCP
import Foundation
import MCP

/// The outcome of a bounded search: the matches plus how much of the collection was scanned.
private struct SearchHits<Item> {
    let matches: [Item]
    let scanned: Int
    let truncated: Bool
}

/// The RankBuddy MCP tool catalogue (#9): read-only, account-aware tools over the HackerRank
/// for Work data, served via buddy-kit's `BuddyMCPServer`.
///
/// Read-only by default — no write/create tools (those would need an explicit, separately
/// reviewed opt-in). Every tool resolves a target account (an `account` argument matching a
/// label or id, else the current account) and dispatches through the same `HackerRankClient`
/// the app uses, so the mock account works in tests without live credentials.
nonisolated struct RankBuddyToolProvider: MCPToolProvider {
    /// The URI of the read-only accounts resource.
    static let accountsURI = "rankbuddy://accounts"

    /// How the provider obtains the account store; injectable so tests use a seeded mock store
    /// instead of the real keychain.
    private let makeStore: @Sendable @MainActor () -> AccountStore

    /// Whether write tools are advertised and runnable (#73). Off by default; the `--mcp` entry
    /// point sets it from the separate `mcpServerAllowWrites` opt-in.
    let allowWrites: Bool

    init(
        allowWrites: Bool = false,
        makeStore: @escaping @Sendable @MainActor () -> AccountStore = { AccountStore.rankBuddy() }
    ) {
        self.allowWrites = allowWrites
        self.makeStore = makeStore
    }

    func tools() async -> [Tool] {
        // Read tools are always advertised; write tools only when the user has opted in (#73).
        mcpTools(from: allowWrites ? Self.descriptors + Self.writeDescriptors : Self.descriptors)
    }

    func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        let account = stringArgument(arguments, "account")
        MCPActivityLog.record(tool: name, detail: Self.callDetail(arguments))

        // Write tools are gated behind the separate opt-in even if a client calls one by name
        // while it isn't advertised (#73).
        if Self.isWriteTool(name) {
            guard allowWrites else {
                return errorResult(
                    "Write tools are off. Turn on “Allow the MCP server to make changes” in " +
                        "RankBuddy ▸ Settings ▸ MCP, then restart your assistant."
                )
            }

            return await callWriteTool(name, arguments: arguments, account: account)
        }

        switch name {
        case "list_accounts": return await listAccounts()
        case "list_tests": return await listTests(account: account)
        case "list_questions": return await listQuestions(account: account)
        case "list_interviews": return await listInterviews(account: account)
        case "list_candidates", "search_tests", "search_questions", "search_interviews":
            return await callKeyedTool(name, arguments: arguments, account: account)
        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    /// The tools that need a keyed argument (a test id, or a search query).
    /// A short, human-readable summary of a tool call's arguments, for the activity log (#52).
    private static func callDetail(_ arguments: [String: Value]?) -> String {
        let keys = ["account", "test_id", "query"]
        let parts = keys.compactMap { key -> String? in
            guard case let .string(value)? = arguments?[key], !value.isEmpty else { return nil }

            return "\(key): \(value)"
        }
        return parts.joined(separator: ", ")
    }

    private func callKeyedTool(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        switch name {
        case "list_candidates":
            guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }

            return await listCandidates(testID: testID, account: account)

        case "search_tests":
            guard let query = stringArgument(arguments, "query") else { return missingArgument("query") }

            return await searchTests(query: query, account: account)

        case "search_questions":
            guard let query = stringArgument(arguments, "query") else { return missingArgument("query") }

            return await searchQuestions(query: query, account: account)

        case "search_interviews":
            guard let query = stringArgument(arguments, "query") else { return missingArgument("query") }

            return await searchInterviews(query: query, account: account)

        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    // MARK: - Account resolution

    /// The account matching `identifier` (label or id), or the current account when nil/unknown.
    /// Internal (not private) so the write-tools extension in another file can resolve too (#73).
    @MainActor
    func resolveAccount(_ identifier: String?) -> Account? {
        let store = makeStore()
        guard let identifier else { return store.currentAccount }

        return store.accounts.first { $0.label == identifier || $0.id.uuidString == identifier }
            ?? store.currentAccount
    }

    // MARK: - List tools

    @MainActor
    private func listAccounts() -> CallTool.Result {
        jsonResult(accountsPayload())
    }

    @MainActor
    private func listTests(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).testsPage()
            let items = page.items.map { ["id": $0.id, "name": $0.name, "state": $0.state ?? ""] }
            return jsonResult([
                "account": resolved.label, "tests": items, "count": items.count, "has_more": page.next != nil
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
                "account": resolved.label, "questions": items, "count": items.count, "has_more": page.next != nil
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
                "account": resolved.label, "interviews": items, "count": items.count, "has_more": page.next != nil
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
                    "id": candidate.id, "email": candidate.email, "name": candidate.fullName ?? "",
                    "score": candidate.score ?? 0, "status": candidate.listStatusLabel ?? ""
                ]
            }
            return jsonResult([
                "account": resolved.label, "test_id": testID, "candidates": items,
                "count": items.count, "has_more": page.next != nil
            ])
        } catch {
            return errorResult("Couldn't list candidates: \(error.localizedDescription)")
        }
    }

    // MARK: - Account payloads

    @MainActor
    private func accountsPayload() -> [String: Any] {
        let store = makeStore()
        let accounts = store.accounts.map { account in
            ["id": account.id.uuidString, "label": account.label, "current": account.id == store.currentAccountID]
        }
        return ["accounts": accounts, "count": accounts.count]
    }

    /// Serialises the accounts payload on the main actor, returning a `Sendable` `String` so the
    /// result can cross back to the nonisolated `readResource` caller without sharing the
    /// non-`Sendable` `[String: Any]`.
    @MainActor
    private func accountsJSON() -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: accountsPayload(), options: [.prettyPrinted, .sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Search

extension RankBuddyToolProvider {
    /// Pages through up to `maxPages` of a collection, returning the items whose `text` contains
    /// the query (case-insensitive). Bounded so a search never drains a huge live collection;
    /// reports how many were scanned and whether more pages remain unseen.
    @MainActor
    private func search<Item>(
        query: String,
        maxPages: Int = 5,
        page: @MainActor (_ cursor: String?) async throws -> Page<Item>,
        text: (Item) -> String
    ) async throws -> SearchHits<Item> {
        var cursor: String?
        var scanned = 0
        var matches: [Item] = []
        var pages = 0
        repeat {
            let result = try await page(cursor)
            scanned += result.items.count
            matches += result.items.filter { text($0).localizedCaseInsensitiveContains(query) }
            cursor = result.next
            pages += 1
        } while cursor != nil && pages < maxPages
        return SearchHits(matches: matches, scanned: scanned, truncated: cursor != nil)
    }

    @MainActor
    private func searchTests(query: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let client = HackerRankClient(account: resolved)
            let hits = try await search(
                query: query,
                page: { try await client.testsPage(after: $0) },
                text: { $0.name }
            )
            let items = hits.matches.map { ["id": $0.id, "name": $0.name, "state": $0.state ?? ""] }
            return searchResult(account: resolved, query: query, items: items, hits: hits, key: "matches")
        } catch {
            return errorResult("Couldn't search tests: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func searchQuestions(query: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let client = HackerRankClient(account: resolved)
            let hits = try await search(
                query: query,
                page: { try await client.questionsPage(after: $0) },
                text: { $0.name }
            )
            let items = hits.matches.map { ["id": $0.id, "name": $0.name, "type": $0.type] }
            return searchResult(account: resolved, query: query, items: items, hits: hits, key: "matches")
        } catch {
            return errorResult("Couldn't search questions: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func searchInterviews(query: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let client = HackerRankClient(account: resolved)
            let hits = try await search(
                query: query,
                page: { try await client.interviewsPage(after: $0) },
                text: { "\($0.title ?? "") \($0.status)" }
            )
            let items = hits.matches.map { ["id": $0.id, "title": $0.title ?? "", "status": $0.status] }
            return searchResult(account: resolved, query: query, items: items, hits: hits, key: "matches")
        } catch {
            return errorResult("Couldn't search interviews: \(error.localizedDescription)")
        }
    }

    private func searchResult(
        account: Account,
        query: String,
        items: [[String: Any]],
        hits: SearchHits<some Any>,
        key: String
    ) -> CallTool.Result {
        jsonResult([
            "account": account.label, "query": query, key: items,
            "count": items.count, "scanned": hits.scanned, "truncated": hits.truncated
        ])
    }
}

// MARK: - Resources & prompts

extension RankBuddyToolProvider {
    func resources() async -> [Resource] {
        [Resource(
            name: "Accounts",
            uri: Self.accountsURI,
            description: "The configured RankBuddy accounts (labels and ids, no tokens).",
            mimeType: "application/json"
        )]
    }

    func readResource(_ uri: String) async throws -> ReadResource.Result {
        guard uri == Self.accountsURI else {
            throw MCPError.invalidParams("Unknown resource URI: \(uri)")
        }

        let json = await accountsJSON()
        return ReadResource.Result(contents: [.text(json, uri: uri, mimeType: "application/json")])
    }

    func prompts() async -> [Prompt] {
        [Prompt(
            name: "triage_candidates",
            description: "Review a test's candidates: who passed, integrity/plagiarism concerns, next steps.",
            arguments: [Prompt.Argument(name: "test_id", description: "The test to triage.", required: true)]
        )]
    }

    func getPrompt(_ name: String, arguments: [String: String]?) async throws -> GetPrompt.Result {
        switch name {
        case "triage_candidates":
            let testID = try requiredPromptArgument(arguments, "test_id")
            let message = """
            Review the candidates for HackerRank test \(testID). Call the `list_candidates` tool \
            with test_id="\(testID)", then summarise who passed the cutoff, flag any integrity or \
            plagiarism concerns, and recommend next steps for each promising candidate.
            """
            return GetPrompt.Result(
                description: "Candidate triage for a test.",
                messages: [userPromptMessage(message)]
            )

        default:
            throw PromptError.unknownPrompt(name)
        }
    }
}
