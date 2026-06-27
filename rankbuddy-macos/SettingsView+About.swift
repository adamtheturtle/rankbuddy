//
//  SettingsView+About.swift
//  rankbuddy-macos
//

import SwiftUI

/// The About tab, split out so `SettingsView.swift` stays under the file-length limit. Holds
/// no private state — just the app version read from the bundle.
extension SettingsView {
    var aboutTab: some View {
        Form {
            Section("RankBuddy") {
                LabeledContent("Version", value: Self.appVersion)
                Text("A native macOS browser for HackerRank for Work tests, candidates, questions, and interviews.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// The app's marketing version and build number, e.g. "1.0 (12)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
