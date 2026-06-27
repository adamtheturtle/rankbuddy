import SwiftUI

extension Test {
    /// Where "now" sits relative to a test's scheduled window. This is independent of the
    /// owner-set lifecycle `state`: an "active" test can still be `.closed` if its end time
    /// has passed, which is what tells a recruiter whether candidates can still take it.
    nonisolated enum WindowStatus {
        case upcoming
        case open
        case closed

        var label: String {
            switch self {
            case .upcoming: "Upcoming"
            case .open: "Open"
            case .closed: "Closed"
            }
        }
    }

    /// The window status at `now`, or `nil` when the test has no usable start or end time.
    /// A future start is `.upcoming`; a past end is `.closed`; anything in between (or a
    /// one-sided window we're inside) is `.open`.
    func windowStatus(now: Date) -> WindowStatus? {
        let start = DisplayFormat.parseDate(startTime)
        let end = DisplayFormat.parseDate(endTime)
        guard start != nil || end != nil else { return nil }

        if let start, now < start { return .upcoming }
        if let end, now > end { return .closed }
        return .open
    }

    /// A badge for the window status at `now`, or `nil` when there is no window.
    func windowBadge(now: Date) -> StatusBadge? {
        switch windowStatus(now: now) {
        case .upcoming:
            StatusBadge(text: "Upcoming", systemImage: "clock", tint: .blue)
        case .open:
            StatusBadge(text: "Open", systemImage: "circle.fill", tint: .green)
        case .closed:
            StatusBadge(text: "Closed", systemImage: "lock.fill", tint: .secondary)
        case nil:
            nil
        }
    }
}
