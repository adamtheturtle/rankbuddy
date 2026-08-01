//
//  BrowserSettings.swift
//  rankbuddy-macos
//

import AppKit

extension URL {
    /// Parses a remote record link while preventing API data from invoking local/custom handlers.
    nonisolated static func remoteWebURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else {
            return nil
        }

        return url
    }
}

/// Link-opening preferences (#63): which browser RankBuddy's external (HackerRank web) links
/// open in, and whether they open in the background. Mirrors PadBuddy's Browser settings.
///
/// In-app browsing isn't offered: RankBuddy has no embedded web view, so every external link
/// opens in a real browser; this just decides which one and whether it steals focus.
enum BrowserSettings {
    private struct BrowserOpenError: LocalizedError {
        let errorDescription: String?
    }

    /// `@AppStorage` key: the chosen browser's bundle id, or empty/absent for the system default.
    static let defaultBrowserKey = "rb.defaultBrowserBundleID"
    /// `@AppStorage` key: whether links open without bringing the browser to the front.
    static let backgroundKey = "rb.openLinksInBackground"

    /// A sample web URL used to discover browsers and the system default. The literal is valid,
    /// so the fallback is unreachable and only avoids a force-unwrap.
    private static var sampleURL: URL {
        URL(string: "https://www.example.com") ?? URL(fileURLWithPath: "/")
    }

    @MainActor private static var cachedInstalledBrowsers: [Browser]?

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
            name = Self.displayName(for: appURL)
        }

        private nonisolated static func displayName(for appURL: URL) -> String {
            var name = FileManager.default.displayName(atPath: appURL.path)
            if name.hasSuffix(".app") {
                name.removeLast(4)
            }
            return name
        }
    }

    /// Discards the cached browser scan, so Settings can pick up newly installed or removed apps.
    @MainActor
    static func invalidateInstalledBrowsers() {
        cachedInstalledBrowsers = nil
    }

    /// The browsers registered to open http(s) URLs, sorted by name.
    @MainActor
    static func installedBrowsers() -> [Browser] {
        if let cachedInstalledBrowsers {
            return cachedInstalledBrowsers
        }

        let browsers = NSWorkspace.shared.urlsForApplications(toOpen: sampleURL)
            .compactMap(Browser.init(appURL:))
            // De-dupe by bundle id (an app can appear once per registered scheme).
            .reduce(into: [Browser]()) { acc, browser in
                if !acc.contains(where: { $0.bundleID == browser.bundleID }) {
                    acc.append(browser)
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cachedInstalledBrowsers = browsers
        return browsers
    }

    /// The display name of the current system default browser, or `nil` if none resolves.
    static func systemDefaultBrowserName() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: sampleURL) else { return nil }

        return Browser(appURL: appURL)?.name
    }

    /// Whether `url` is a web address this app should hand to a browser preference.
    static func isOpenableWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty else { return false }

        return true
    }

    /// The stored browser choice, but only when it still names an installed http(s)-capable app.
    @MainActor
    static func validatedBrowserBundleID(defaults: UserDefaults = .standard) -> String? {
        let chosenID = defaults.string(forKey: defaultBrowserKey) ?? ""
        guard !chosenID.isEmpty else { return nil }
        guard installedBrowsers().contains(where: { $0.bundleID == chosenID }) else {
            defaults.removeObject(forKey: defaultBrowserKey)
            return nil
        }

        return chosenID
    }

    /// Opens `url` honouring the preferences: in the chosen browser (falling back to the system
    /// default), bringing it to the front unless background opening is on. Non-web schemes use
    /// their normal system handler and never inherit the browser preference.
    @MainActor
    static func open(_ url: URL, defaults: UserDefaults = .standard) {
        guard isOpenableWebURL(url) else {
            if !NSWorkspace.shared.open(url) {
                presentOpenFailure(url: url, error: nil, canRetryWithDefault: false)
            }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = !defaults.bool(forKey: backgroundKey)

        let preferredAppURL = validatedBrowserBundleID(defaults: defaults)
            .flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
        let appURL = preferredAppURL ?? NSWorkspace.shared.urlForApplication(toOpen: url)

        if let appURL {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { application, error in
                guard application == nil || error != nil else { return }

                Task { @MainActor in
                    presentOpenFailure(
                        url: url,
                        error: error,
                        canRetryWithDefault: preferredAppURL != nil
                    )
                }
            }
        } else if !NSWorkspace.shared.open(url) {
            presentOpenFailure(url: url, error: nil, canRetryWithDefault: false)
        }
    }

    @MainActor
    private static func presentOpenFailure(
        url: URL,
        error: Error?,
        canRetryWithDefault: Bool
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Open Link"
        let reason = error?.localizedDescription
            ?? BrowserOpenError(errorDescription: "No application accepted the URL.").localizedDescription
        alert.informativeText = "\(url.absoluteString)\n\n\(reason)"
        if canRetryWithDefault {
            alert.addButton(withTitle: "Try System Default")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn,
               !NSWorkspace.shared.open(url) {
                presentOpenFailure(url: url, error: nil, canRetryWithDefault: false)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
