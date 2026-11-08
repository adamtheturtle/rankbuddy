//
//  SidebarSection.swift
//  rankbuddy-macos
//

/// The top-level sections shown in the sidebar of the main window.
///
/// Order is the display order, so the cases are deliberately not sorted. `nonisolated` (a pure
/// value type) so other `nonisolated` types — e.g. `FavoriteCollection` — can read its labels.
nonisolated enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case tests
    case questions
    case interviews
    case people = "users"
    case teams
    case templates
    case candidates
    case auditLogs
    case atsInvitations
    case provisioning

    /// The `@AppStorage`/`UserDefaults` key the selected section is persisted under, shared by
    /// the main window, menu bar, deep links, and the Dock menu.
    static let defaultsKey = "selectedSection"

    var id: String {
        rawValue
    }

    /// The sidebar label for the section.
    var title: String {
        switch self {
        case .tests: "Tests"
        case .questions: "Questions"
        case .interviews: "Interviews"
        case .templates: "Templates"
        case .people: "People"
        case .teams: "Teams"
        case .candidates: "Find Candidates"
        case .auditLogs: "Audit Logs"
        case .atsInvitations: "ATS Invitations"
        case .provisioning: "Provisioning"
        }
    }

    /// The SF Symbol shown next to the section's label.
    var systemImage: String {
        switch self {
        case .tests: "checklist"
        case .questions: "questionmark.bubble"
        case .interviews: "person.crop.rectangle.stack"
        case .templates: "doc.on.doc"
        case .people: "person.2"
        case .teams: "person.3"
        case .candidates: "person.crop.circle.badge.magnifyingglass"
        case .auditLogs: "list.bullet.rectangle.portrait"
        case .atsInvitations: "envelope.badge.person.crop"
        case .provisioning: "person.badge.key"
        }
    }
}
