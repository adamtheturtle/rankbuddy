//
//  AppSettings.swift
//  rankbuddy-macos
//

import SwiftUI

/// The user's preferred appearance, applied to the whole app from the General settings tab.
/// `RawRepresentable`/`String` so it persists directly through `@AppStorage`.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// The `@AppStorage` key shared by the Settings picker and the app root.
    static let defaultsKey = "rb.appearance"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The SwiftUI color scheme to force, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// General list behaviour shared by the Settings control and `LoadableList` (#69).
enum GeneralSettings {
    /// `@AppStorage` key: how often the visible list auto-refreshes, in seconds. `0` (the
    /// default) is off — the lists then refresh only on demand.
    static let refreshSecondsKey = "rb.listRefreshSeconds"
    /// The historical default: auto-refresh off.
    static let defaultRefreshSeconds = 0
    /// The shortest auto-refresh interval the stepper allows; anything below it counts as off.
    static let minRefreshSeconds = 30
    /// The longest auto-refresh interval the stepper allows.
    static let maxRefreshSeconds = 600
    /// The stepper increment.
    static let refreshStep = 30

    /// A human-readable label for an interval: "Off", "30s", "2m", or "2m 30s". Pure, so it's
    /// unit-testable.
    static func refreshIntervalLabel(_ seconds: Int) -> String {
        guard seconds >= minRefreshSeconds else { return "Off" }

        let minutes = seconds / 60
        let remainder = seconds % 60
        switch (minutes, remainder) {
        case (0, _): return "\(remainder)s"
        case (_, 0): return "\(minutes)m"
        default: return "\(minutes)m \(remainder)s"
        }
    }

    /// The auto-refresh cadence as a `Duration`, or `nil` when off. Any value below the
    /// minimum (including the `0` default) is treated as off, so the timer simply never runs.
    static func refreshInterval(raw: Int) -> Duration? {
        raw >= minRefreshSeconds ? .seconds(raw) : nil
    }
}

/// Menu-bar preferences shared by the Settings stepper and `MenuBarContent`.
enum MenuBarPreferences {
    /// The `@AppStorage` key for how many recent items the menu bar lists.
    static let recentCountKey = "rb.menuBarRecentCount"
    /// The default (and historical) recent-item count.
    static let defaultRecentCount = 8
    /// The largest value the stepper allows (PadBuddy parity, #88).
    static let maxRecentCount = 30

    /// The `@AppStorage` key for filtering the menu-bar list to active/upcoming items (#67).
    static let activeOnlyKey = "rb.menuBarActiveOnly"
}
