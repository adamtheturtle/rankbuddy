//
//  BrowserSettings.swift
//  rankbuddy-macos
//

import AppKit

/// Link-opening preferences (#63): which browser RankBuddy's external (HackerRank web) links
/// open in, and whether they open in the background. Mirrors PadBuddy's Browser settings.
///
/// In-app browsing isn't offered — RankBuddy has no embedded web view — so every external link
/// opens in a real browser; this just decides *which* one and whether it steals focus.
enum BrowserSettings {
    /// `@AppStorage` key: the chosen browser's bundle id, or empty/absent for the system default.
    static let defaultBrowserKey = "rb.defaultBrowserBundleID"
    /// `@AppStorage` key: whether links open without bringing the browser to the front.
    static let backgroundKey = "rb.openLinksInBackground"

    /// A sample web URL used to discover browsers and the system default. The literal is valid,
    /// so the fallback is unreachable and only avoids a force-unwrap.
    private static var sampleURL: URL {
        URL(string: "https://www.example.com") ?? URL(fileURLWithPath: "/")
    }

    /// An installed browser the user can pick as their default for RankBuddy links.
    struct Browser: Identifiable, Hashable {
        let bundleID: String
        let name: String
        var id: String {
            bundleID
        }

        nonisolated init?(appURL: URL) {
            guard let id = Bundle(url: appURL)?.bundleIdentifier else { return nil }

            bundleID = id
            name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
        }
    }

    /// The browsers registered to open http(s) URLs, sorted by name.
    static func installedBrowsers() -> [Browser] {
        NSWorkspace.shared.urlsForApplications(toOpen: sampleURL)
            .compactMap(Browser.init(appURL:))
            // De-dupe by bundle id (an app can appear once per registered scheme).
            .reduce(into: [Browser]()) { acc, browser in
                if !acc.contains(where: { $0.bundleID == browser.bundleID }) { acc.append(browser) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The display name of the current system default browser, or `nil` if none resolves.
    static func systemDefaultBrowserName() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: sampleURL) else { return nil }

        return FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Opens `url` honouring the preferences: in the chosen browser (falling back to the system
    /// default), bringing it to the front unless background opening is on.
    static func open(_ url: URL, defaults: UserDefaults = .standard) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !defaults.bool(forKey: backgroundKey)

        let chosenID = defaults.string(forKey: defaultBrowserKey) ?? ""
        let appURL = (chosenID.isEmpty ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: chosenID))
            ?? NSWorkspace.shared.urlForApplication(toOpen: url)

        if let appURL {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
