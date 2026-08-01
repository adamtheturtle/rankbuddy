import Testing
@testable import rankbuddy_macos

func expectUnauthorized(_ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("expected an unauthorized error")
    } catch {
        #expect(hackerRankHTTPStatus(error) == 401)
    }
}
