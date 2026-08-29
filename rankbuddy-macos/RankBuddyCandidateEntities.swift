//
//  RankBuddyCandidateEntities.swift
//  rankbuddy-macos
//

import AppIntents
import BuddyAppKit
import CoreSpotlight
import Foundation
import HackerRankKit
import Observation

/// A privacy-minimal candidate entity. Candidate email, name, score, report, and source are not
/// donated to Spotlight; the owning test title and opaque candidate id provide enough context to
/// select and open a result without indexing candidate PII.
struct RankBuddyCandidateEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "RankBuddy Candidate")
    static let defaultQuery = RankBuddyCandidateEntityQuery()

    let id: String
    let accountID: String
    let testID: String
    let candidateID: String
    let testTitle: String

    init(accountID: String, testID: String, candidateID: String, testTitle: String) {
        self.accountID = accountID
        self.testID = testID
        self.candidateID = candidateID
        self.testTitle = testTitle
        id = "candidates|\(accountID)|\(testID)|\(candidateID)"
    }

    init?(id: String) {
        let parts = id.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "candidates",
              UUID(uuidString: String(parts[1])) != nil,
              !parts[2].isEmpty, !parts[3].isEmpty else { return nil }

        self.init(
            accountID: String(parts[1]),
            testID: String(parts[2]),
            candidateID: String(parts[3]),
            testTitle: "Test \(parts[2])"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Candidate \(candidateID)",
            subtitle: "Candidate in \(testTitle)",
            image: .init(systemName: "person.text.rectangle")
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.domainIdentifier = accountID
        return set
    }
}

struct RankBuddyCandidateEntityQuery: EntityQuery {
    static let testLimit = 20
    static let candidateLimitPerTest = 20

    func entities(for identifiers: [String]) async throws -> [RankBuddyCandidateEntity] {
        identifiers.compactMap(RankBuddyCandidateEntity.init(id:))
    }

    @MainActor
    func suggestedEntities() async throws -> [RankBuddyCandidateEntity] {
        var entities: [RankBuddyCandidateEntity] = []
        var complete = true
        for account in SharedAccountStore.resolve().accounts {
            let client = HackerRankClient(account: account)
            do {
                let tests = try await client.testsPage(after: nil).items.prefix(Self.testLimit)
                for test in tests {
                    let candidates = try await client.candidatesPage(testID: test.id, after: nil)
                        .items.prefix(Self.candidateLimitPerTest)
                    entities.append(contentsOf: candidates.map { candidate in
                        RankBuddyCandidateEntity(
                            accountID: account.id.uuidString,
                            testID: test.id,
                            candidateID: candidate.id,
                            testTitle: test.name
                        )
                    })
                }
            } catch {
                complete = false
            }
        }
        if complete {
            try await RankBuddyCandidateSpotlightIndex.replaceAll(with: entities)
        }
        return entities
    }
}

enum RankBuddyCandidateSpotlightIndex {
    static let name = "RankBuddyCandidates"

    static func replaceAll(with entities: [RankBuddyCandidateEntity]) async throws {
        let index = CSSearchableIndex(name: name)
        try await index.deleteAllSearchableItems()
        try await index.indexAppEntities(entities)
    }

    static func clear() async {
        try? await CSSearchableIndex(name: name).deleteAllSearchableItems()
    }

    static func remove(accountID: UUID) async {
        try? await CSSearchableIndex(name: name)
            .deleteSearchableItems(withDomainIdentifiers: [accountID.uuidString])
    }
}

struct OpenRankBuddyCandidateIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open RankBuddy Candidate"
    // periphery:ignore - App Intents discovers this metadata at runtime.
    static let description = IntentDescription("Opens a candidate in RankBuddy without indexing candidate details.")

    @Parameter(title: "Candidate")
    var target: RankBuddyCandidateEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        CandidateDeepLinkRouter.shared.open(
            accountID: target.accountID,
            testID: target.testID,
            candidateID: target.candidateID
        )
        return .result()
    }
}

@MainActor
@Observable
final class CandidateDeepLinkRouter {
    static let shared = CandidateDeepLinkRouter()

    struct Request: Equatable {
        // periphery:ignore - Synthesized Equatable uses this to distinguish repeated requests.
        let id = UUID()
        let accountID: String
        let testID: String
        let candidateID: String
    }

    var request: Request?

    func open(accountID: String, testID: String, candidateID: String) {
        request = Request(accountID: accountID, testID: testID, candidateID: candidateID)
    }

    func consume(_ request: Request) {
        if self.request == request {
            self.request = nil
        }
    }
}
