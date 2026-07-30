//
//  RankBuddyToolProvider.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import HackerRankKit
import MCP
import MCPKit

// Tool dispatch is intentionally centralized so capability registration and routing cannot drift.
// swiftlint:disable file_length

/// The outcome of a bounded search: the matches plus how much of the collection was scanned.
private struct SearchHits<Item> {
    let matches: [Item]
    let scanned: Int
    let truncated: Bool
}

// The RankBuddy MCP tool catalogue (#9): read-only, account-aware tools over the HackerRank
// for Work data, served via buddy-kit's `MCPServer`.
//
// Read-only by default — no write/create tools (those would need an explicit, separately
// reviewed opt-in). Every tool resolves a target account (an `account` argument matching a
// label or id, else the current account) and dispatches through the same `HackerRankClient`
// the app uses, so the mock account works in tests without live credentials.
// swiftlint:disable:next type_body_length
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

    // swiftlint:disable:next cyclomatic_complexity
    func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        guard Self.isKnownTool(name) else {
            return errorResult("Unknown tool: \(name)")
        }

        if let unknown = Self.unknownArgument(in: arguments, toolName: name) {
            return errorResult("Unknown argument “\(unknown)” for tool \(name).")
        }

        let account = stringArgument(arguments, "account")
        MCPActivityLog.record(tool: name, detail: Self.callDetail(tool: name, arguments: arguments))

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
        case "list_users", "list_teams":
            // Org enumeration (#9), in its own dispatch + file.
            return await callOrgListTool(name, account: account)
        case "list_candidates", "candidate_report_pdf", "get_invite_template", "get_interview_template",
             "search_tests", "search_questions", "search_interviews":
            return await callKeyedTool(name, arguments: arguments, account: account)
        case "list_invite_templates", "list_interview_templates":
            return await callTemplateTool(name, arguments: arguments, account: account)
        case "search_users", "search_candidates":
            // Server-side people/candidate search (#104), in its own dispatch + file.
            return await callPeopleSearchTool(name, arguments: arguments, account: account)
        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    static func isKnownTool(_ name: String) -> Bool {
        (descriptors + writeDescriptors).contains {
            $0["name"] as? String == name
        }
    }

    static func unknownArgument(in arguments: [String: Value]?, toolName: String) -> String? {
        guard let arguments else { return nil }

        let descriptor = (descriptors + writeDescriptors).first { $0["name"] as? String == toolName }
        let schema = descriptor?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        let allowed = Set(properties?.keys.map(\.self) ?? [])
        return arguments.keys.sorted().first { !allowed.contains($0) }
    }

    /// A short, human-readable summary of a tool call's arguments, for the activity log (#52).
    static func callDetail(tool: String, arguments: [String: Value]?) -> String {
        let readFields = ["account", "test_id", "candidate_id", "query"]
        let keys = writeAuditFields[tool] ?? readFields
        let parts = keys.compactMap { key -> String? in
            guard let argument = arguments?[key] else { return nil }

            let value: String
            switch argument {
            case let .string(text): value = key.contains("email") ? redactedEmail(text) : text
            case let .int(number): value = String(number)
            default: return nil
            }
            guard !value.isEmpty else { return nil }

            return "\(key): \(MCPActivityLog.normalizedSummary(value, maxCharacters: 160))"
        }
        return parts.joined(separator: ", ")
    }

    private static let writeAuditFields: [String: [String]] = [
        "create_test": ["account", "name"],
        "update_test": ["account", "test_id", "name"],
        "archive_test": ["account", "test_id"],
        "delete_test": ["account", "test_id"],
        "invite_candidate": ["account", "test_id", "email"],
        "update_candidate": ["account", "test_id", "candidate_id"],
        "cancel_candidate_invite": ["account", "test_id", "candidate_id"],
        "delete_candidate_report": ["account", "test_id", "candidate_id"],
        "create_user": ["account", "email", "team_id"],
        "update_user": ["account", "user_id"],
        "lock_user": ["account", "user_id"],
        "create_question": ["account", "name", "type"],
        "update_question": ["account", "question_id", "name"],
        "delete_question": ["account", "question_id"],
        "delete_testcase": ["account", "question_id", "testcase_id"],
        "delete_all_testcases": ["account", "question_id"],
        "create_team": ["account", "name"],
        "update_team": ["account", "team_id", "name"],
        "delete_team": ["account", "team_id"],
        "add_team_member": ["account", "team_id", "email"],
        "add_team_member_by_user_id": ["account", "team_id", "user_id"],
        "remove_team_member": ["account", "team_id", "user_id"],
        "create_pad": ["account", "title"],
        "schedule_interview": ["account", "title", "candidate_email"],
        "delete_interview": ["account", "interview_id"],
        "create_ats_codepair_invite": ["account", "candidate_id", "requisition_id", "title"],
        "create_ats_codescreen_invite": ["account", "test_id", "candidate_id", "requisition_id", "email"]
    ]

    private static func redactedEmail(_ value: String) -> String {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let first = parts[0].first, !parts[1].isEmpty else {
            return "[redacted email]"
        }

        return "\(first)***@\(parts[1])"
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func callKeyedTool(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        switch name {
        case "list_candidates":
            guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }

            return await listCandidates(
                testID: testID,
                cursor: stringArgument(arguments, "cursor"),
                account: account
            )

        case "candidate_report_pdf":
            guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
            guard let candidateID = stringArgument(arguments, "candidate_id") else {
                return missingArgument("candidate_id")
            }

            return await candidateReportPDF(testID: testID, candidateID: candidateID, account: account)

        case "get_invite_template":
            guard let templateID = stringArgument(arguments, "template_id") else {
                return missingArgument("template_id")
            }

            return await getInviteTemplate(templateID: templateID, account: account)

        case "get_interview_template":
            guard case let .int(templateID)? = arguments?["template_id"] else {
                return missingArgument("template_id")
            }

            return await getInterviewTemplate(templateID: templateID, account: account)

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

    private func callTemplateTool(
        _ name: String,
        arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        switch name {
        case "list_invite_templates":
            await listInviteTemplates(access: stringArgument(arguments, "access"), account: account)
        case "list_interview_templates":
            await listInterviewTemplates(account: account)
        default:
            errorResult("Unknown tool: \(name)")
        }
    }

    // MARK: - Account resolution

    /// The account matching `identifier` (label or UUID), or the current account when omitted.
    /// An explicit unknown identifier fails closed so writes can never drift to another org.
    /// Internal (not private) so the write-tools extension in another file can resolve too (#73).
    @MainActor
    func resolveAccount(_ identifier: String?) -> Account? {
        let store = makeStore()
        guard let identifier else { return store.currentAccount }

        if let id = UUID(uuidString: identifier) {
            return store.accounts.first { $0.id == id }
        }
        return store.accounts.first { $0.label == identifier }
    }

    // MARK: - List tools

    @MainActor
    private func listAccounts() -> CallTool.Result {
        jsonResult(accountsPayload())
    }

    func pageMetadata(_ page: Page<some Sendable>) -> [String: Any] {
        var metadata: [String: Any] = [
            "returned_count": page.items.count,
            "has_more": page.next != nil
        ]
        if let totalCount = page.totalCount {
            metadata["total_count"] = totalCount
        }
        return metadata
    }

    @MainActor
    private func listTests(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).testsPage()
            let items = page.items.map { ["id": $0.id, "name": $0.name, "state": $0.state ?? ""] }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "tests": items
            ]) { _, value in value })
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
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "questions": items
            ]) { _, value in value })
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
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "interviews": items
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list interviews: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listCandidates(testID: String, cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).candidatesPage(
                testID: testID,
                after: cursor
            )
            let items = page.items.map { candidate in
                [
                    "id": candidate.id, "email": candidate.email, "name": candidate.fullName ?? "",
                    "score": candidate.score ?? 0, "status": candidate.listStatusLabel ?? ""
                ]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "test_id": testID, "candidates": items,
                "next_cursor": page.next ?? ""
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list candidates: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func candidateReportPDF(testID: String, candidateID: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let pdf = try await HackerRankClient(account: resolved).candidateReportPDF(
                testID: testID,
                candidateID: candidateID
            )
            return jsonResult([
                "account": resolved.label,
                "test_id": testID,
                "candidate_id": candidateID,
                "url": pdf.url ?? pdf.pdfURL ?? ""
            ])
        } catch {
            return errorResult("Couldn't fetch candidate report PDF: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listInviteTemplates(access: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).inviteTemplatesPage(access: access)
            let items = page.items.map {
                ["id": $0.id ?? "", "name": $0.name ?? "", "subject": $0.subject ?? "", "access": $0.access ?? ""]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "templates": items
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list invite templates: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func getInviteTemplate(templateID: String, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let template = try await HackerRankClient(account: resolved).inviteTemplate(id: templateID)
            return jsonResult([
                "account": resolved.label,
                "template": [
                    "id": template.id ?? templateID,
                    "name": template.name ?? "",
                    "subject": template.subject ?? "",
                    "body": template.body ?? "",
                    "access": template.access ?? ""
                ]
            ])
        } catch {
            return errorResult("Couldn't get invite template: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listInterviewTemplates(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).interviewTemplatesPage()
            let items = page.items.map {
                [
                    "id": $0.id ?? 0,
                    "name": $0.name ?? "",
                    "title": $0.title ?? "",
                    "description": $0.description ?? ""
                ] as [String: Any]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "templates": items
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list interview templates: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func getInterviewTemplate(templateID: Int, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let template = try await HackerRankClient(account: resolved).interviewTemplate(id: templateID)
            return jsonResult([
                "account": resolved.label,
                "template": [
                    "id": template.id ?? templateID,
                    "name": template.name ?? "",
                    "title": template.title ?? "",
                    "description": template.description ?? ""
                ] as [String: Any]
            ])
        } catch {
            return errorResult("Couldn't get interview template: \(error.localizedDescription)")
        }
    }

    // MARK: - Account payloads

    @MainActor
    private func accountsPayload() -> [String: Any] {
        let store = makeStore()
        let accounts = store.accounts.map { account in
            ["id": account.id.uuidString, "label": account.label, "current": account.id == store.currentAccountID]
        }
        return ["accounts": accounts, "total_count": accounts.count]
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

nonisolated struct BoundedSearchProgress<ID: Hashable> {
    private var seenIDs: Set<ID> = []
    private var seenCursors: Set<String> = []

    mutating func accept<Item>(
        _ items: [Item],
        next: String?,
        id: (Item) -> ID
    ) -> (items: [Item], next: String?) {
        let unique = items.filter { seenIDs.insert(id($0)).inserted }
        guard !unique.isEmpty, let next, seenCursors.insert(next).inserted else {
            return (unique, nil)
        }

        return (unique, next)
    }
}

extension RankBuddyToolProvider {
    /// Pages through up to `maxPages` of a collection, returning the items whose `text` contains
    /// the query (case-insensitive). Bounded so a search never drains a huge live collection;
    /// reports how many were scanned and whether more pages remain unseen.
    @MainActor
    private func search<Item>(
        query: String,
        maxPages: Int = 5,
        page: @MainActor (_ cursor: String?) async throws -> Page<Item>,
        id: (Item) -> String,
        text: (Item) -> String
    ) async throws -> SearchHits<Item> {
        var cursor: String?
        var scanned = 0
        var matches: [Item] = []
        var pages = 0
        var progress = BoundedSearchProgress<String>()
        repeat {
            let result = try await page(cursor)
            let accepted = progress.accept(result.items, next: result.next, id: id)
            scanned += accepted.items.count
            matches += accepted.items.filter { text($0).localizedCaseInsensitiveContains(query) }
            cursor = accepted.next
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
                id: \.id,
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
                id: \.id,
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
                id: \.id,
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
            Review every candidate for HackerRank test \(testID). Call `list_candidates` with \
            test_id="\(testID)". While its `has_more` field is true, call it again with the same \
            test_id and `cursor` set to the preceding `next_cursor`. Do not summarise until all \
            pages are loaded. Then report who passed the cutoff, flag integrity or plagiarism \
            concerns, and recommend next steps for each promising candidate.
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
