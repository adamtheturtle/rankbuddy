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

    /// Whether to present the sheet: there's something to show and this version's notes haven't
    /// been seen yet. An empty `lastSeenVersion` (fresh install / first run) counts as unseen.
    static func shouldShow(currentVersion: String, lastSeenVersion: String) -> Bool {
        !highlights.isEmpty && currentVersion != lastSeenVersion
    }
}

/// The What's New sheet: a titled list of highlights with a dismiss button that records the
/// current version as seen.
struct WhatsNewView: View {
    /// Called when dismissed, so the caller can record the version as seen.
    var onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("What's New in RankBuddy")
                .font(.title2).bold()

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

            Button("Continue") {
                onDismiss()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 440)
    }
}

#Preview {
    WhatsNewView {}
}
