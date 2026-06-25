import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the candidate status/ATS-state code labels (#37). The mapping is
/// table-driven and deliberately conservative: stable codes get labels; transient codes,
/// the unset value, and unknown codes return nil so the detail view omits the row.
struct CandidateStatusTests {
    private func candidate(status: Int? = nil, atsState: Int? = nil) throws -> TestCandidate {
        var fields = [#""id":"c1""#, #""email":"c@x.com""#]
        if let status { fields.append("\"status\":\(status)") }
        if let atsState { fields.append("\"ats_state\":\(atsState)") }
        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(TestCandidate.self, from: Data(json.utf8))
    }

    // MARK: - Attempt status

    @Test func `known attempt-status codes get labels`() throws {
        #expect(try candidate(status: -1).attemptStatusLabel == "Invited")
        #expect(try candidate(status: 0).attemptStatusLabel == "In progress")
        #expect(try candidate(status: 7).attemptStatusLabel == "Reports ready")
    }

    @Test func `transient or absent attempt-status codes have no label`() throws {
        // 2-6 are documented as transient intermediate states.
        #expect(try candidate(status: 4).attemptStatusLabel == nil)
        #expect(try candidate(status: nil).attemptStatusLabel == nil)
    }

    // MARK: - Pipeline (ATS) status

    @Test func `known pipeline codes get labels`() throws {
        #expect(try candidate(atsState: 2).pipelineStatusLabel == "Test completed — qualified")
        #expect(try candidate(atsState: 9).pipelineStatusLabel == "Offer accepted")
        #expect(try candidate(atsState: 21).pipelineStatusLabel == "Hired")
        #expect(try candidate(atsState: 22).pipelineStatusLabel == "Rejected")
    }

    @Test func `unset, ambiguous, or absent pipeline codes have no label`() throws {
        // 0 is "not set"; 4-6 are ambiguous ranges left unmapped.
        #expect(try candidate(atsState: 0).pipelineStatusLabel == nil)
        #expect(try candidate(atsState: 5).pipelineStatusLabel == nil)
        #expect(try candidate(atsState: nil).pipelineStatusLabel == nil)
    }

    // MARK: - Compact list label

    @Test func `the list label prefers the pipeline state`() throws {
        // Pipeline set → it wins over the attempt state for the compact summary.
        #expect(try candidate(status: 7, atsState: 21).listStatusLabel == "Hired")
    }

    @Test func `the list label falls back to the attempt state`() throws {
        #expect(try candidate(status: 0, atsState: 0).listStatusLabel == "In progress")
    }

    @Test func `the list label is nil when nothing is known`() throws {
        #expect(try candidate(status: nil, atsState: nil).listStatusLabel == nil)
    }
}
