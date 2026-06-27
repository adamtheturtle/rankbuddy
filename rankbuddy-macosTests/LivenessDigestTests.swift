import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the pure liveness derivations (#32): the scheduled-interview count and the
/// Dock badge label behind the background-updates feature.
struct LivenessDigestTests {
    private func interview(id: String, status: String) throws -> Interview {
        let json = #"{"id":"\#(id)","status":"\#(status)","url":"https://example.com/x"}"#
        return try JSONDecoder().decode(Interview.self, from: Data(json.utf8))
    }

    @Test func `scheduled count ignores other states and is case-insensitive`() throws {
        let interviews = try [
            interview(id: "1", status: "scheduled"),
            interview(id: "2", status: "Scheduled"),
            interview(id: "3", status: "completed"),
            interview(id: "4", status: "cancelled")
        ]
        #expect(LivenessDigest.scheduledCount(interviews) == 2)
    }

    @Test func `an empty list has no scheduled interviews`() {
        #expect(LivenessDigest.scheduledCount([]) == 0)
    }

    @Test func `the badge label is nil at zero and the number otherwise`() {
        #expect(LivenessDigest.badgeLabel(scheduledCount: 0) == nil)
        #expect(LivenessDigest.badgeLabel(scheduledCount: 1) == "1")
        #expect(LivenessDigest.badgeLabel(scheduledCount: 12) == "12")
    }
}
