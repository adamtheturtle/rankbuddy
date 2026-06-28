//
//  InterviewTemplates.swift
//  rankbuddy-macos
//

import Foundation
import Observation

/// Which write flow a template seeds: an instant QuickPad or a scheduled interview (#60/#97).
/// Raw values are the persisted contract — never rename them.
nonisolated enum InterviewTemplateKind: String, Codable, Hashable, CaseIterable {
    case quickPad = "quick_pad"
    case scheduled

    /// The human-readable name for menus and the editor.
    var label: String {
        switch self {
        case .quickPad: "QuickPad"
        case .scheduled: "Scheduled Interview"
        }
    }

    /// The SF Symbol used wherever the template's kind is shown.
    var systemImage: String {
        switch self {
        case .quickPad: "bolt"
        case .scheduled: "calendar.badge.plus"
        }
    }
}

/// A saved interview template (#97): a per-account recipe — a name and the seed settings for
/// one of the existing create flows — so running the same kind of interview is a single action.
///
/// Deliberately lightweight and `Codable` so it persists as `UserDefaults` JSON and is suitable
/// for later iCloud sync (#22), exactly like `FavoriteRef`.
nonisolated struct InterviewTemplate: Codable, Hashable, Identifiable {
    /// A stable identifier, assigned once at creation so edits don't reorder or duplicate it.
    let id: String
    /// The account the template belongs to (templates are account-scoped).
    let accountID: String
    /// The template's display name, shown in the palette, menu, and editor.
    var name: String
    /// Which create flow this template launches.
    var kind: InterviewTemplateKind
    /// Seeds the created pad/interview title. May be empty (QuickPad titles are optional).
    var titlePrefix: String

    init(
        accountID: String,
        name: String,
        kind: InterviewTemplateKind,
        titlePrefix: String = "",
        id: String = UUID().uuidString
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.kind = kind
        self.titlePrefix = titlePrefix
    }

    /// The title to seed the create sheet with — the prefix, or the template name when the
    /// prefix is blank, so running a template never opens an entirely empty form.
    var seededTitle: String {
        let trimmed = titlePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : titlePrefix
    }
}

/// Account-aware interview templates (#97).
///
/// Persists a small list of `InterviewTemplate`s as JSON in `UserDefaults` — non-secret state,
/// kept lightweight and serialisable so it is suitable for later iCloud sync (#22). MainActor-
/// isolated; observed by the views that list, run, and manage templates. Mirrors
/// `FavoritesStore` exactly so the two account-scoped config stores behave identically.
@Observable
@MainActor
final class InterviewTemplatesStore {
    private let defaults: UserDefaults
    private let storageKey = "rankbuddy.interviewTemplates"

    /// The templates in insertion order (oldest first).
    private(set) var templates: [InterviewTemplate]

    /// Called after any local mutation persists, so a sync coordinator can mirror the change
    /// (#22). Not part of the observable surface.
    @ObservationIgnored var onChange: (() -> Void)?

    /// - Parameters:
    ///   - defaults: the backing store; injectable so tests stay isolated.
    ///   - isTesting: when true the store starts empty and never reads existing defaults, so
    ///     demo mode and tests don't pick up (or pollute) real templates.
    init(defaults: UserDefaults = .standard, isTesting: Bool = false) {
        self.defaults = defaults
        if isTesting {
            templates = []
        } else if let data = defaults.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode([InterviewTemplate].self, from: data) {
            templates = decoded
        } else {
            templates = []
        }
    }

    /// The templates for one account, most-recently-added first.
    func templates(accountID: String) -> [InterviewTemplate] {
        templates.filter { $0.accountID == accountID }.reversed()
    }

    /// Adds a new template (most-recently-added shows first).
    func add(_ template: InterviewTemplate) {
        templates.append(template)
        persist()
    }

    /// Replaces an existing template by id; no-op when the id is unknown.
    func update(_ template: InterviewTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }

        templates[index] = template
        persist()
    }

    /// Removes the template with the given id; no-op when the id is unknown.
    func remove(id: String) {
        let kept = templates.filter { $0.id != id }
        guard kept.count != templates.count else { return }

        templates = kept
        persist()
    }

    /// Drops every template whose account is no longer configured, so a removed account leaves
    /// no dangling entries (mirrors `FavoritesStore.prune`). No-op when nothing changes.
    func prune(toAccountIDs ids: Set<String>) {
        let kept = templates.filter { ids.contains($0.accountID) }
        guard kept.count != templates.count else { return }

        templates = kept
        persist()
    }

    /// Replaces the whole set, e.g. when adopting an incoming iCloud change (#22). No-op when
    /// unchanged, so it doesn't churn observers or re-trigger a sync.
    func replace(with templates: [InterviewTemplate]) {
        guard templates != self.templates else { return }

        self.templates = templates
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(templates) else { return }

        defaults.set(data, forKey: storageKey)
        onChange?()
    }
}

/// Shared state for running a template: a view sets `pending` (from the ⌘K palette or a menu)
/// and the Interviews screen observes it to present the matching, pre-filled create sheet (#97).
/// Lives in the environment so the palette and the screen drive the same single path.
@Observable
@MainActor
final class InterviewTemplateLauncher {
    /// The template waiting to be run, or nil when nothing is pending. The Interviews screen
    /// clears it once it presents the create sheet.
    var pending: InterviewTemplate?
}

/// The pieces the command palette needs to surface and run interview templates (#97): the
/// store to list them and the launcher to route a chosen one to the Interviews screen. Bundled
/// so the palette builder stays within its parameter budget.
@MainActor
struct InterviewTemplatePalette {
    let store: InterviewTemplatesStore
    let launcher: InterviewTemplateLauncher
}
