@testable import rankbuddy_macos
import Testing

/// Pins the user-visible sidebar metadata (#32). `SidebarSection` drives both the main
/// window's sidebar and the command palette's `section.*` candidates, and its raw values
/// are persisted via `@AppStorage("selectedSection")` (#19), so the case set, their order,
/// raw values, titles, and SF Symbols are a stable contract.
struct SidebarSectionTests {
    @Test func `the sections are in display order`() {
        #expect(SidebarSection.allCases == [.tests, .questions, .interviews, .people, .teams])
    }

    @Test func `raw values are stable persistence keys`() {
        // These back @AppStorage("selectedSection"); changing them would drop a user's
        // restored section on upgrade. People's raw value is "users" so it matches the
        // /users endpoint and its restoration key.
        #expect(SidebarSection.tests.rawValue == "tests")
        #expect(SidebarSection.questions.rawValue == "questions")
        #expect(SidebarSection.interviews.rawValue == "interviews")
        #expect(SidebarSection.people.rawValue == "users")
        #expect(SidebarSection.teams.rawValue == "teams")
    }

    @Test func `id matches the raw value`() {
        for section in SidebarSection.allCases {
            #expect(section.id == section.rawValue)
        }
    }

    @Test func `every section has a title and an SF Symbol`() {
        #expect(SidebarSection.tests.title == "Tests")
        #expect(SidebarSection.questions.title == "Questions")
        #expect(SidebarSection.interviews.title == "Interviews")
        #expect(SidebarSection.people.title == "People")
        #expect(SidebarSection.teams.title == "Teams")

        for section in SidebarSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.systemImage.isEmpty)
        }
    }
}
