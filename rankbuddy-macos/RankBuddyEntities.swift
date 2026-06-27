//
//  RankBuddyEntities.swift
//  rankbuddy-macos
//

import AppIntents
import BuddyAppKit
import CoreSpotlight
import Foundation

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

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(collection.section.title)",
            image: .init(systemName: collection.systemImage)
        )
    }
}

/// Locates `RankBuddyObjectEntity` instances for Spotlight/Shortcuts by fetching the current
/// account's collections (#24). Runs in-process, so it reuses the app's keychain-backed
/// account and the same client/mock the UI uses; a token-less or offline account simply
/// yields no entities.
struct RankBuddyObjectEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RankBuddyObjectEntity] {
        let all = try await Self.currentAccountEntities()
        let wanted = Set(identifiers)
        return all.filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RankBuddyObjectEntity] {
        let entities = try await Self.currentAccountEntities()
        // Best-effort: donate to a named Spotlight index whenever the system asks for
        // suggestions, so the same fetch also keeps Spotlight current — no extra network and
        // no launch-time work. Only the non-sensitive display metadata is indexed (#24).
        try? await CSSearchableIndex(name: RankBuddySpotlightIndex.name).indexAppEntities(entities)
        return entities
    }

    /// Fetches the first page of the current account's tests, questions, and interviews and
    /// maps them to entities. Returns `[]` when there is no current account.
    @MainActor
    static func currentAccountEntities() async throws -> [RankBuddyObjectEntity] {
        guard let account = AccountStore.rankBuddy().currentAccount else { return [] }

        let client = HackerRankClient(account: account)
        let accountID = account.id.uuidString
        async let tests = client.testsPage()
        async let questions = client.questionsPage()
        async let interviews = client.interviewsPage()

        var entities: [RankBuddyObjectEntity] = []
        entities += try await tests.items.map {
            RankBuddyObjectEntity(collection: .tests, accountID: accountID, itemID: $0.id, title: $0.name)
        }
        entities += try await questions.items.map {
            RankBuddyObjectEntity(collection: .questions, accountID: accountID, itemID: $0.id, title: $0.name)
        }
        entities += try await interviews.items.map {
            RankBuddyObjectEntity(
                collection: .interviews,
                accountID: accountID,
                itemID: $0.id,
                title: $0.title ?? "Interview \($0.id)"
            )
        }
        return entities
    }
}

/// The shared Spotlight index RankBuddy donates findable items to (#24). Centralised so the
/// donation (`suggestedEntities`) and the deletion-on-account-removal use the same index name.
enum RankBuddySpotlightIndex {
    /// The `CSSearchableIndex` name holding RankBuddy's donated items.
    static let name = "RankBuddyObjects"

    /// Removes every donated item from Spotlight. Called when an account is deleted so that a
    /// removed account's items can't linger in system search (#24: indexed content is removed
    /// when an account is deleted). The index repopulates with the current account the next time
    /// the system requests suggestions, so only the current account is ever indexed.
    static func clear() async {
        try? await CSSearchableIndex(name: name).deleteAllSearchableItems()
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
    @MainActor
    static func open(collection: FavoriteCollection, accountID: String, itemID: String) {
        UserDefaults.standard.set(itemID, forKey: "selection.\(collection.rawValue).\(accountID)")
        UserDefaults.standard.set(collection.section.rawValue, forKey: "selectedSection")
    }
}
