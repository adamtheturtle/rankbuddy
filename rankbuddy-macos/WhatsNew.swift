//
//  WhatsNew.swift
//  rankbuddy-macos
//

import SwiftUI

/// A "What's New" surface shown once per app version (#45/#47), mirroring PadBuddy's
/// release-notes screen. The decision (`shouldShow`) is pure so it's unit-testable; the view
/// records the version as seen when dismissed.
enum WhatsNew {
    /// `@AppStorage`/`UserDefaults` key for the last app version whose notes were shown.
    static let lastSeenKey = "rb.lastSeenVersion"

    /// One highlight in the What's New list.
    struct Highlight: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let systemImage: String
    }

    /// The notable changes shown for the current release.
    static let highlights: [Highlight] = [
        Highlight(
            title: "Filter & save searches",
            detail: "Narrow any list by date range, then save a search to re-run it later.",
            systemImage: "line.3.horizontal.decrease.circle"
        ),
        Highlight(
            title: "Print & export",
            detail: "Print or save a candidate report as PDF, and export any list to CSV.",
            systemImage: "square.and.arrow.up"
        ),
        Highlight(
            title: "Stay in the loop",
            detail: "An optional Dock badge of upcoming interviews, with notifications for new ones.",
            systemImage: "bell.badge"
        ),
        Highlight(
            title: "More at home on the Mac",
            detail: "A welcome screen, relative dates, theme options, and a Dock menu.",
            systemImage: "macwindow"
        )
    ]

    /// The current app marketing version (`CFBundleShortVersionString`).
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// The current app build number (`CFBundleVersion`), which may advance while the marketing
    /// version stays fixed.
    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// A release-note revision identity. Build is included because corrected notes can ship in a
    /// later build of the same marketing version.
    static func releaseIdentifier(version: String, build: String) -> String {
        "\(version)|\(build)"
    }

    static var currentReleaseIdentifier: String {
        releaseIdentifier(version: currentVersion, build: currentBuild)
    }

    /// Whether to present the sheet: there's something to show and this version/build's notes
    /// haven't been seen yet. An empty value (fresh install / first run) counts as unseen.
    static func shouldShow(
        currentVersion: String,
        currentBuild: String,
        lastSeenRelease: String
    ) -> Bool {
        guard !highlights.isEmpty else { return false }
        guard !lastSeenRelease.isEmpty else { return true }

        return isNewer(
            version: currentVersion,
            build: currentBuild,
            than: lastSeenRelease
        )
    }

    /// Compares marketing versions numerically first, then build numbers when the versions match.
    /// A legacy version-only stored value is treated as build zero so it migrates forward once.
    static func isNewer(version: String, build: String, than releaseIdentifier: String) -> Bool {
        let components = releaseIdentifier.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let previousVersion = String(components[0])
        let previousBuild = components.count == 2 ? String(components[1]) : "0"

        switch version.compare(previousVersion, options: .numeric) {
        case .orderedDescending:
            return true
        case .orderedAscending:
            return false
        case .orderedSame:
            return build.compare(previousBuild, options: .numeric) == .orderedDescending
        }
    }
}

/// The What's New sheet: a titled list of highlights with a dismiss button.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("What's New in RankBuddy")
                .font(.title2).bold()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(WhatsNew.highlights) { highlight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: highlight.systemImage)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(highlight.title).font(.headline)
                                Text(highlight.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            Button("Continue") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 440)
        .frame(minHeight: 320, idealHeight: 520, maxHeight: 600)
    }
}

#Preview {
    WhatsNewView()
}
