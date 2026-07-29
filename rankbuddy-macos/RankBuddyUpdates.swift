//
//  RankBuddyUpdates.swift
//  rankbuddy-macos
//

import Foundation
import Sparkle
import SwiftUI

/// Sparkle auto-update wiring for the direct-download (Developer ID) build (#11).
///
/// The updater is created **only when an appcast feed is configured** (the `SUFeedURL`
/// Info.plist key), so a build without the release infrastructure (feed URL, EdDSA public
/// key, Developer ID signing) shows no "Check for Updates" item and logs no Sparkle errors at
/// launch. Once Adam adds `SUFeedURL` + `SUPublicEDKey` and notarized/signed builds, the menu
/// item appears and works. Sparkle must not be linked into a future App Store target (#20).
@MainActor
enum RankBuddyUpdates {
    /// The standard Sparkle controller, or `nil` when no appcast feed is configured.
    static let controller: SPUStandardUpdaterController? = {
        guard feedConfigured(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL")),
              signingKeyConfigured(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey"))
        else { return nil }

        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    /// Whether an appcast feed value is present and usable. Factored out so it's testable
    /// without a configured bundle.
    static func feedConfigured(_ infoValue: Any?) -> Bool {
        guard let string = infoValue as? String else { return false }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty
        else { return false }

        return components.url != nil
    }

    /// Whether Sparkle has a valid Ed25519 public key. Sparkle's generated `SUPublicEDKey` is a
    /// base64-encoded 32-byte key; requiring that shape prevents exposing an updater that cannot
    /// securely verify downloaded releases.
    static func signingKeyConfigured(_ infoValue: Any?) -> Bool {
        guard let string = infoValue as? String else { return false }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: trimmed)?.count == 32
    }
}

/// Adds a standard "Check for Updates…" item to the app menu, but only when Sparkle is
/// configured (#11). With no feed configured the group is empty, so nothing is shown.
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if let controller = RankBuddyUpdates.controller {
                Button("Check for Updates…") {
                    controller.updater.checkForUpdates()
                }
            }
        }
    }
}
