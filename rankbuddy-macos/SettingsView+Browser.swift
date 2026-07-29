//
//  SettingsView+Browser.swift
//  rankbuddy-macos
//

import SwiftUI

/// The Browser settings tab (#63), split out so `SettingsView.swift` stays under the
/// file-length limit. Chooses which browser RankBuddy's web links open in, and whether they
/// open in the background.
extension SettingsView {
    var browserTab: some View {
        Form {
            Section {
                Picker("Open links in", selection: $defaultBrowserID) {
                    Text(systemDefaultLabel).tag("")
                    Divider()
                    ForEach(installedBrowsers) { browser in
                        Text(browser.name).tag(browser.bundleID)
                    }
                }

                Toggle("Open links in the background", isOn: $openLinksInBackground)
            } header: {
                Text("Links")
            } footer: {
                Text("HackerRank web links (reports, the site) open in this browser. " +
                    "“In the background” opens them without bringing the browser to the front.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            BrowserSettings.invalidateInstalledBrowsers()
            installedBrowsers = BrowserSettings.installedBrowsers()
        }
    }

    /// The first picker row: "System Default (Safari)" when the default resolves, else just
    /// "System Default".
    private var systemDefaultLabel: String {
        if let name = BrowserSettings.systemDefaultBrowserName() {
            "System Default (\(name))"
        } else {
            "System Default"
        }
    }
}
