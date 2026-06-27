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

/// Menu-bar preferences shared by the Settings stepper and `MenuBarContent`.
enum MenuBarPreferences {
    /// The `@AppStorage` key for how many recent items the menu bar lists.
    static let recentCountKey = "rb.menuBarRecentCount"
    /// The default (and historical) recent-item count.
    static let defaultRecentCount = 8
    /// The largest value the stepper allows.
    static let maxRecentCount = 20
}
