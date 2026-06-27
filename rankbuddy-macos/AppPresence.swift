//
//  AppPresence.swift
//  rankbuddy-macos
//

import AppKit

/// Where RankBuddy shows itself: in the Dock, in the Menu Bar, or both (#66). Mirrors
/// PadBuddy's "Show PadBuddy in" control. `RawRepresentable`/`String` so it persists directly
/// through `@AppStorage`.
enum AppPresence: String, CaseIterable, Identifiable {
    case both
    case dockOnly
    case menuBarOnly

    /// The `@AppStorage` key shared by the Settings picker and the app scenes.
    static let defaultsKey = "rb.appPresence"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .both: "Dock & Menu Bar"
        case .dockOnly: "Dock only"
        case .menuBarOnly: "Menu Bar only"
        }
    }

    /// Whether the Dock icon is shown. A menu-bar-only app runs as an accessory.
    var showsDockIcon: Bool {
        self != .menuBarOnly
    }

    /// Whether the Menu Bar extra is inserted.
    var showsMenuBarIcon: Bool {
        self != .dockOnly
    }

    /// The activation policy that realises this presence: `.regular` shows a Dock icon,
    /// `.accessory` hides it for a menu-bar-only experience.
    var activationPolicy: NSApplication.ActivationPolicy {
        showsDockIcon ? .regular : .accessory
    }

    /// Reads the stored presence, defaulting to `.both` for an unset or unrecognised value.
    static func current(defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .both
    }

    /// Applies this presence's Dock visibility. When returning to the Dock, re-activates the
    /// app so the main window comes forward rather than staying hidden behind other apps.
    @MainActor
    func applyDockVisibility() {
        guard NSApp.activationPolicy() != activationPolicy else { return }

        NSApp.setActivationPolicy(activationPolicy)
        if showsDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
