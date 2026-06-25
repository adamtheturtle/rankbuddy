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

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "RankBuddy Section")
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .tests: "Tests",
            .questions: "Questions",
            .interviews: "Interviews"
        ]
    }
}

/// Opens RankBuddy to a chosen section.
///
/// `openAppWhenRun` cold-launches the app or brings the existing single main window
/// forward; the deep-link itself is the shared persisted selection, which the main window
/// observes live, so an already-frontmost app switches sections immediately.
struct OpenRankBuddySectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Section"
    static var description = IntentDescription("Opens RankBuddy to a specific section.")
    static var openAppWhenRun = true

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
    static var title: LocalizedStringResource = "Open RankBuddy"
    static var description = IntentDescription("Opens the RankBuddy main window.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
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
    }
}
