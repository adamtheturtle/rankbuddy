import AppKit

/// The custom "About RankBuddy" panel (#51), mirroring PadBuddy's. Opens the standard macOS
/// About panel — which already shows the app icon, name, version, and build from Info.plist —
/// pre-filled with a short credits/description line.
enum AboutPanel {
    /// The credits line shown under the version in the About panel.
    static let creditsText = """
    A native macOS browser for HackerRank for Work — tests, candidates, questions, \
    and interviews.

    © 2026 Adam Dangoor
    """

    @MainActor
    static func show() {
        let credits = NSAttributedString(
            string: creditsText,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11)
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
