//
//  HackerRankClient+Account.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import HackerRankKitMock

extension HackerRankClient {
    /// Builds a client for a stored `Account`, routing the demo accounts to the
    /// in-process fake API (`HackerRankKitMock`) and real accounts to the live session.
    /// Tests can inject an explicit `session`.
    init(account: Account, session: URLSession? = nil) {
        if let session {
            self.init(token: account.token, baseURL: account.baseURL, session: session)
        } else if account.token == Account.badKeyDemoToken {
            self = .mock(unauthorized: true)
        } else if account.isMock {
            self = .mock()
        } else {
            self.init(token: account.token, baseURL: account.baseURL)
        }
    }

    /// Product-facing Pad naming for the HackerRankKit QuickPad endpoint.
    @discardableResult
    func createPad(title: String? = nil) async throws -> CreatedInterview {
        try await createQuickPad(title: title)
    }
}
