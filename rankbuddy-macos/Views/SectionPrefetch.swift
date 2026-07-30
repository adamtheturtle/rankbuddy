//
//  SectionPrefetch.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// Warms each sidebar section's first-page cache for the active account in the background, so the
/// first visit to a tab in a session is instant instead of spinning (#102).
///
/// Runs once the active account is known. A section already cached — in memory from this launch,
/// or on disk from a recent one — is skipped, so a warm cache never triggers a redundant fetch; a
/// failed fetch is ignored, leaving that section to load normally when it's opened. Fetches run
/// one after another to stay polite to the API rather than firing five requests at once.
@MainActor
enum SectionPrefetch {
    /// Loads and caches each background section's first page, skipping the visible section and
    /// any page already cached.
    static func warm(account: Account, excluding visibleSection: SidebarSection) async {
        let client = HackerRankClient(account: account)
        let id = account.id

        // Keys mirror each screen's `restorationKey` ("selection.<section>.<account.id>") and must
        // stay in sync, or a prefetched page lands under a key the screen never reads.
        if visibleSection != .tests {
            await warmOne(key: "selection.tests.\(id)") { try await client.testsPage() }
        }
        if visibleSection != .questions {
            await warmOne(key: "selection.questions.\(id)") { try await client.questionsPage() }
        }
        if visibleSection != .interviews {
            await warmOne(key: "selection.interviews.\(id)") { try await client.interviewsPage() }
        }
        if visibleSection != .people {
            await warmOne(key: "selection.users.\(id)") { try await client.usersPage() }
        }
        if visibleSection != .teams {
            await warmOne(key: "selection.teams.\(id)") { try await client.teamsPage() }
        }
    }

    /// Fetches and caches one section's first page, unless it's already cached.
    private static func warmOne<Item: Codable>(
        key: String,
        load: () async throws -> Page<Item>
    ) async {
        guard await ListPageCache.cached([Item].self, for: key) == nil else { return }
        guard let page = try? await load() else { return }

        await ListPageCache.store(
            items: page.items, cursor: page.next, totalCount: page.totalCount, for: key
        )
    }
}
