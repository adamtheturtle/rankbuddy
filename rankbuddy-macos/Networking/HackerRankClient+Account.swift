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
    init(
        account: Account,
        session: URLSession? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let selectedSession: URLSession
        if let session {
            selectedSession = session
        } else if account.token == Account.badKeyDemoToken {
            self = .mock(unauthorized: true)
            return
        } else if account.isMock {
            guard let scenario = DemoFailureScenario(environment: environment) else {
                self = .mock()
                return
            }

            selectedSession = scenario.session()
        } else {
            selectedSession = Self.liveSession
        }

        // Account.baseURL is either the built-in HTTPS URL or a parsed HTTPS override.
        do {
            self = try Self(token: account.token, baseURL: account.baseURL, session: selectedSession)
        } catch {
            preconditionFailure("Invalid account base URL: \(error)")
        }
    }
}
