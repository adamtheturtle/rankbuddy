//
//  RankBuddyIntents.swift
//  rankbuddy-macos
//

import AppIntents
import Foundation

/// The persisted-selection key the main window observes (`ContentView`'s
/// `@AppStorage("selectedSection")`). Writing it deep-links the app to a section.
private let selectedSectionDefaultsKey = "selectedSection"

/// The top-level sections that can be opened from Shortcuts and Spotlight (#24).
///
/// Mirrors `SidebarSection`, but kept as a dedicated `AppEnum` so the automation surface
/// has its own localized, user-facing titles and stays decoupled from the internal
/// navigation enum. The raw values match `SidebarSection`'s so they can drive the shared
/// persisted selection directly.
enum RankBuddySectionOption: String, AppEnum {
    case tests
    case questions
    case interviews
    case people = "users"
    case teams

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "RankBuddy Section")
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .tests: "Tests",
            .questions: "Questions",
            .interviews: "Interviews",
            .people: "People",
            .teams: "Teams"
        ]
    }
}

/// Opens RankBuddy to a chosen section.
///
/// `openAppWhenRun` cold-launches the app or brings the existing single main window
/// forward; the deep-link itself is the shared persisted selection, which the main window
/// observes live, so an already-frontmost app switches sections immediately.
struct OpenRankBuddySectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Section"
    // periphery:ignore
    static let description = IntentDescription("Opens RankBuddy to a specific section.")
    static let openAppWhenRun = true

    @Parameter(title: "Section", default: .tests)
    var section: RankBuddySectionOption

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(section.rawValue, forKey: selectedSectionDefaultsKey)
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open RankBuddy to \(\.$section)")
    }
}

/// Brings RankBuddy's main window to the front (or launches it).
struct OpenRankBuddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open RankBuddy"
    // periphery:ignore
    static let description = IntentDescription("Opens the RankBuddy main window.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Clears stale list snapshots and refreshes the privacy-filtered Spotlight/App Entity index.
/// This gives Shortcuts a useful read-oriented refresh action without exposing credentials or
/// write access to HackerRank (#24).
struct RefreshRankBuddyDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh RankBuddy Data"
    // periphery:ignore
    static let description = IntentDescription("Refreshes RankBuddy's cached lists and searchable items.")

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await RankBuddyDataRefresh.refresh {
            try await RankBuddyObjectEntityQuery().suggestedEntities()
        }
        _ = try await RankBuddyCandidateEntityQuery().suggestedEntities()
        return .result()
    }
}

@MainActor
enum RankBuddyDataRefresh {
    /// Invalidates local list snapshots before refetching. The operation is injectable so the
    /// cache contract and error propagation can be tested without live HackerRank credentials.
    @discardableResult
    static func refresh(
        clearCache: @MainActor () async -> Void = { await ListPageCache.clear() },
        fetchEntities: @MainActor () async throws -> [RankBuddyObjectEntity]
    ) async throws -> Int {
        await clearCache()
        let entities = try await fetchEntities()
        return entities.count
    }
}

/// Exposes the intents to Spotlight and the Shortcuts app with spoken phrases. The phrases
/// reference the `RankBuddySectionOption` parameter, which is a finite `AppEnum`, so the
/// system can enumerate a phrase per section.
struct RankBuddyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRankBuddySectionIntent(),
            phrases: [
                "Open \(.applicationName) \(\.$section)",
                "Show \(.applicationName) \(\.$section)"
            ],
            shortTitle: "Open Section",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: OpenRankBuddyIntent(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open RankBuddy",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: RefreshRankBuddyDataIntent(),
            phrases: [
                "Refresh \(.applicationName)"
            ],
            shortTitle: "Refresh RankBuddy",
            systemImageName: "arrow.clockwise"
        )
    }
}
