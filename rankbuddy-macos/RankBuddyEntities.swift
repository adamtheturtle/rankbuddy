//
//  RankBuddyEntities.swift
//  rankbuddy-macos
//

import AppIntents
import BuddyAppKit
import CoreSpotlight
import Foundation
import HackerRankKit
import OSLog

/// A findable RankBuddy object — a test, question, or interview — exposed to Spotlight and
/// Shortcuts (#24). One entity type covers the three top-level collections (each carries its
/// `collection` so the open intent can route correctly); per-type entities could be split out
/// later if the Shortcuts phrasing needs it.
///
/// Conforms to `IndexedEntity` so the system can add it to Spotlight; the default attribute
/// set indexes the `displayRepresentation` (title + subtitle). Only non-sensitive metadata
/// (the object's display name and collection) is exposed — no tokens, candidate PII, or
/// report contents (the privacy allowlist in #24).
struct RankBuddyObjectEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "RankBuddy Item")
    static let defaultQuery = RankBuddyObjectEntityQuery()

    /// A stable composite id: `collection|accountID|itemID`. Encodes everything the open
    /// intent needs to route without a second lookup.
    let id: String
    /// The object's display name.
    let title: String
    /// Which collection the object belongs to.
    let collection: FavoriteCollection
    /// The account the object belongs to (for account-aware routing).
    let accountID: String
    /// The object's own API identifier within its collection.
    let itemID: String
    /// On-device-generated topical keywords (#92) attached to the Spotlight attribute set so the
    /// item is found by topic, not just by words in its title. Not part of the identity, so the
    /// composite `id` and routing are unchanged; empty until enrichment runs (and stays empty
    /// when the on-device model is unavailable).
    var keywords: [String] = []

    init(collection: FavoriteCollection, accountID: String, itemID: String, title: String) {
        self.collection = collection
        self.accountID = accountID
        self.itemID = itemID
        self.title = title
        id = "\(collection.rawValue)|\(accountID)|\(itemID)"
    }

    /// Reconstructs the routing fields from a composite id, or `nil` if it doesn't parse.
    init?(id: String, title: String) {
        let parts = id.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let collection = FavoriteCollection(rawValue: String(parts[0])) else {
            return nil
        }

        self.init(collection: collection, accountID: String(parts[1]), itemID: String(parts[2]), title: title)
    }

    /// Reconstructs an offline-capable route when Spotlight supplies only the persistent id.
    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let collection = FavoriteCollection(rawValue: String(parts[0])),
              !parts[1].isEmpty,
              !parts[2].isEmpty
        else { return nil }

        let itemID = String(parts[2])
        let noun = String(collection.rawValue.dropLast()).capitalized
        self.init(collection: collection, accountID: String(parts[1]), itemID: itemID, title: "\(noun) \(itemID)")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(collection.section.title)",
            image: .init(systemName: collection.systemImage)
        )
    }

    /// Augments the default title/subtitle attributes with the on-device-generated keywords
    /// (#92). The default set must be added explicitly — the system does not merge it in.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.domainIdentifier = accountID
        if !keywords.isEmpty {
            set.keywords = keywords
        }
        return set
    }
}

/// Locates `RankBuddyObjectEntity` instances for Spotlight/Shortcuts.
struct RankBuddyObjectEntityQuery: EntityQuery {
    private static let logger = Logger(
        subsystem: "com.adamdangoor.rankbuddy",
        category: "spotlight"
    )

    func entities(for identifiers: [String]) async throws -> [RankBuddyObjectEntity] {
        identifiers.compactMap(RankBuddyObjectEntity.init(id:))
    }

    func suggestedEntities() async throws -> [RankBuddyObjectEntity] {
        let snapshots = try await Self.allAccountSnapshots()
        let enrichables = snapshots.flatMap(\.enrichables)
        let entities = enrichables.map(\.entity)
        // Replace the complete configured-account snapshot so switching accounts and backend
        // deletions cannot leave stale results.
        try? await RankBuddySpotlightIndex.replaceAll(with: entities)
        // On-device keyword enrichment (#92): additive, gated on model availability, re-indexing
        // the same ids with topical keywords. The source text is already in hand from the fetch
        // above (no extra network). Detached so a slow generation never delays the suggestions
        // the system asked for.
        Task { await SpotlightKeywordEnricher.enrich(enrichables) }
        return entities
    }

    /// Fetches the first page of the current account's tests, questions, and interviews and
    /// maps them to entities. Returns `[]` when there is no current account.
    @MainActor
    static func currentAccountEntities() async throws -> [RankBuddyObjectEntity] {
        try await currentAccountEnrichables().map(\.entity)
    }

    /// Fetches the current account's first pages and pairs each entity with the on-device text
    /// its Spotlight keywords are generated from (#92). Returns `[]` when there is no current
    /// account. The keyword source is built from fields already in the page response, so this
    /// adds no network work over the plain entity fetch.
    @MainActor
    static func currentAccountEnrichables() async throws -> [EnrichableEntity] {
        try await currentAccountSnapshot()?.enrichables ?? []
    }

    struct AccountSnapshot {
        let accountID: String
        let enrichables: [EnrichableEntity]
    }

    @MainActor
    private static func collect(
        _ collection: String,
        operation: @MainActor () async throws -> [EnrichableEntity]
    ) async -> [EnrichableEntity] {
        do {
            return try await operation()
        } catch {
            logger.error("Failed to refresh \(collection, privacy: .public): \(error, privacy: .public)")
            return []
        }
    }

    @MainActor
    static func currentAccountSnapshot() async throws -> AccountSnapshot? {
        guard let account = SharedAccountStore.resolve().currentAccount else { return nil }

        return await snapshot(for: account)
    }

    @MainActor
    static func allAccountSnapshots() async throws -> [AccountSnapshot] {
        var snapshots: [AccountSnapshot] = []
        for account in SharedAccountStore.resolve().accounts {
            await snapshots.append(snapshot(for: account))
        }
        return snapshots
    }

    @MainActor
    private static func snapshot(for account: Account) async -> AccountSnapshot {
        let client = HackerRankClient(account: account)
        let accountID = account.id.uuidString
        async let tests = collect("tests") {
            try await client.testsPage().items.map { test in
                EnrichableEntity(
                    entity: RankBuddyObjectEntity(
                        collection: .tests, accountID: accountID, itemID: test.id, title: test.name
                    ),
                    keywordSource: SpotlightKeywordSource.text(for: test) ?? ""
                )
            }
        }
        async let questions = collect("questions") {
            try await client.questionsPage().items.map { question in
                EnrichableEntity(
                    entity: RankBuddyObjectEntity(
                        collection: .questions, accountID: accountID, itemID: question.id, title: question.name
                    ),
                    keywordSource: SpotlightKeywordSource.text(for: question) ?? ""
                )
            }
        }
        async let interviews = collect("interviews") {
            try await client.interviewsPage().items.map { interview in
                EnrichableEntity(
                    entity: RankBuddyObjectEntity(
                        collection: .interviews,
                        accountID: accountID,
                        itemID: interview.id,
                        title: interview.title ?? "Interview \(interview.id)"
                    ),
                    keywordSource: SpotlightKeywordSource.text(for: interview) ?? ""
                )
            }
        }

        var enrichables: [EnrichableEntity] = []
        enrichables += await tests
        enrichables += await questions
        enrichables += await interviews
        return AccountSnapshot(accountID: accountID, enrichables: enrichables)
    }
}

/// The shared Spotlight index RankBuddy donates findable items to (#24). Centralised so the
/// donation (`suggestedEntities`) and the deletion-on-account-removal use the same index name.
enum RankBuddySpotlightIndex {
    /// The `CSSearchableIndex` name holding RankBuddy's donated items.
    static let name = "RankBuddyObjects"

    /// Reconciles the complete configured-account index after a refresh.
    static func replaceAll(with entities: [RankBuddyObjectEntity]) async throws {
        let index = CSSearchableIndex(name: name)
        try await index.deleteAllSearchableItems()
        try await index.indexAppEntities(entities)
    }

    /// Removes every donated item from Spotlight. Called when an account is deleted so that a
    /// removed account's items can't linger in system search (#24: indexed content is removed
    /// when an account is deleted). The index repopulates with the current account the next time
    /// the system requests suggestions.
    static func clear() async {
        try? await CSSearchableIndex(name: name).deleteAllSearchableItems()
    }

    /// Removes one account's donated items after deletion or re-keying, preserving every other
    /// tenant in the named index.
    static func remove(accountID: UUID) async {
        try? await CSSearchableIndex(name: name)
            .deleteSearchableItems(withDomainIdentifiers: [accountID.uuidString])
    }
}

/// Opens a RankBuddy object from a Spotlight result or a shortcut, routing to the right
/// account and section via the same per-account selection key the lists restore from (#19/#24).
struct OpenRankBuddyObjectIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open RankBuddy Item"
    static let description = IntentDescription("Opens a test, question, or interview in RankBuddy.")

    @Parameter(title: "Item")
    var target: RankBuddyObjectEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        RankBuddyDeepLink.open(collection: target.collection, accountID: target.accountID, itemID: target.itemID)
        return .result()
    }
}

/// The deep-link writes the main window observes: the per-account selection key the list
/// restores from, plus the selected section. Shared by the open intent and tested directly.
enum RankBuddyDeepLink {
    /// The restoration key a list persists its selected detail under, for the given collection and
    /// account. Matches each screen's `restorationKey`, so a deep link can target the right list.
    static func selectionKey(collection: FavoriteCollection, accountID: String) -> String {
        "selection.\(collection.rawValue).\(accountID)"
    }

    @MainActor
    static func open(
        collection: FavoriteCollection,
        accountID: String,
        itemID: String,
        store: AccountStore = SharedAccountStore.resolve()
    ) {
        if let encodedID = UUID(uuidString: accountID),
           store.accounts.contains(where: { $0.id == encodedID }) {
            store.showAllAccounts = false
            store.currentAccountID = encodedID
        }
        UserDefaults.standard.set(itemID, forKey: selectionKey(collection: collection, accountID: accountID))
        UserDefaults.standard.set(collection.section.rawValue, forKey: "selectedSection")
        // Poke the router so a list that is *already on screen* (e.g. clicking a favourite for the
        // section you're already viewing) jumps to the item immediately (#122). A cold launch or a
        // cross-section switch is still served by the UserDefaults restore above, which runs when
        // the target list mounts and loads.
        DeepLinkRouter.shared.open(
            key: selectionKey(collection: collection, accountID: accountID),
            itemID: itemID
        )
    }
}

/// A live deep-link target that already-mounted lists observe (#122). `RankBuddyDeepLink.open`
/// persists the selection for cold-launch/section-switch restore *and* posts here, so a list
/// showing the targeted collection reveals the item without waiting for a reload that a same-
/// section click never triggers.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// A request to reveal one item in the list whose `restorationKey` equals `key`.
    struct Request: Identifiable, Equatable {
        /// A fresh identity per request, so re-opening the *same* item still registers as a change
        /// the observing list reacts to (otherwise clicking a favourite twice would be a no-op).
        let id = UUID()
        /// The `restorationKey` of the list to target.
        let key: String
        /// The id of the item to select and scroll to.
        let itemID: String
    }

    /// The most recent open request, cleared once the matching list consumes it.
    var request: Request?

    /// Posts a request for the list keyed by `key` to reveal `itemID`.
    func open(key: String, itemID: String) {
        request = Request(key: key, itemID: itemID)
    }
}
