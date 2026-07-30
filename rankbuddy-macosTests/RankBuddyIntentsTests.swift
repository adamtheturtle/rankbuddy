//
//  RankBuddyIntentsTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the App Intents deep-link surface (#24, #32). `OpenRankBuddySectionIntent`
/// is the Shortcuts/Spotlight entry point: it writes a section's raw value to the same
/// `UserDefaults` key the main window observes via `@AppStorage("selectedSection")`. The
/// contract that keeps the deep-link working is that `RankBuddySectionOption`'s raw values
/// stay aligned with `SidebarSection`'s, and that `perform()` writes a value that resolves
/// back to a real section. Nothing exercised the intent before.
@MainActor
struct RankBuddyIntentsTests {
    /// The intent's automation enum is deliberately separate from `SidebarSection`; these
    /// are the cases it offers.
    private let options: [RankBuddySectionOption] = [.tests, .questions, .interviews, .people, .teams]

    @Test func `every section option resolves to a real sidebar section`() {
        for option in options {
            #expect(SidebarSection(rawValue: option.rawValue) != nil)
        }
    }

    @Test func `the option raw values exactly mirror the sidebar sections`() {
        // Drift here would leave a Shortcuts phrase that deep-links nowhere, or a sidebar
        // section unreachable from automation.
        let optionRaws = Set(options.map(\.rawValue))
        let sectionRaws = Set(SidebarSection.allCases.map(\.rawValue))
        #expect(optionRaws == sectionRaws)
    }

    @MainActor
    @Test func `performing the intent deep-links to a resolvable section`() async throws {
        let key = "selectedSection"
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let intent = OpenRankBuddySectionIntent()
        intent.section = .questions
        _ = try await intent.perform()

        // The value written must be exactly what @AppStorage("selectedSection") restores.
        let stored = try #require(defaults.string(forKey: key))
        #expect(stored == "questions")
        #expect(SidebarSection(rawValue: stored) == .questions)
    }

    @Test func `refresh invalidates list snapshots before fetching entities`() async throws {
        let key = "selection.tests.intent-refresh"
        await ListPageCache.store(items: ["stale"], cursor: "next", totalCount: 1, for: key)
        var cacheWasEmptyDuringFetch = false

        let count = try await RankBuddyDataRefresh.refresh {
            cacheWasEmptyDuringFetch = await ListPageCache.cached([String].self, for: key) == nil
            return [
                RankBuddyObjectEntity(
                    collection: .tests,
                    accountID: "account",
                    itemID: "test",
                    title: "Test"
                )
            ]
        }

        #expect(cacheWasEmptyDuringFetch)
        #expect(count == 1)
    }
}
