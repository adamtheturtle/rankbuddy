//
//  AppPresence.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit

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

    /// Reconciles a system-driven Menu Bar extra insertion change with the persisted preference.
    /// Removing the only visible surface enables the Dock, so the app can never become unreachable.
    func settingMenuBarInserted(_ isInserted: Bool) -> Self {
        if isInserted {
            return showsDockIcon ? .both : .menuBarOnly
        }
        return .dockOnly
    }

    /// Reads the stored presence, defaulting to `.both` for an unset or unrecognised value.
    static func current(defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .both
    }

    /// A preference matching the activation policy that actually remains after a failed change,
    /// retaining the requested Menu Bar surface whenever the Dock is still available.
    func matchingActualPolicy(_ policy: NSApplication.ActivationPolicy) -> Self {
        policy == .regular
            ? (showsMenuBarIcon ? .both : .dockOnly)
            : .menuBarOnly
    }

    /// Applies this presence's Dock visibility. When returning to the Dock, re-activates the
    /// app so the main window comes forward rather than staying hidden behind other apps. Returns
    /// false when macOS rejects the activation-policy transition.
    @MainActor
    func applyDockVisibility(
        currentPolicy: () -> NSApplication.ActivationPolicy = { NSApplication.shared.activationPolicy() },
        setPolicy: (NSApplication.ActivationPolicy) -> Bool = { NSApplication.shared.setActivationPolicy($0) },
        activate: () -> Void = { AppActivator.bringToFront() }
    ) -> Bool {
        guard currentPolicy() != activationPolicy else { return true }
        guard setPolicy(activationPolicy) else { return false }

        if showsDockIcon {
            activate()
        }
        return true
    }
}
