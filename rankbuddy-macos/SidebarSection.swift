import SwiftUI

/// The top-level sections shown in the sidebar of the main window.
///
/// Order is the display order, so the cases are deliberately not sorted.
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case tests
    case questions
    case interviews
    case people = "users"
    case teams

    var id: String {
        rawValue
    }

    /// The sidebar label for the section.
    var title: String {
        switch self {
        case .tests: "Tests"
        case .questions: "Questions"
        case .interviews: "Interviews"
        case .people: "People"
        case .teams: "Teams"
        }
    }

    /// The SF Symbol shown next to the section's label.
    var systemImage: String {
        switch self {
        case .tests: "checklist"
        case .questions: "questionmark.square"
        case .interviews: "person.crop.rectangle.stack"
        case .people: "person.2"
        case .teams: "person.3"
        }
    }
}
