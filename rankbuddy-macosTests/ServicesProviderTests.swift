//
//  ServicesProviderTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the "Open in RankBuddy" Service's URL resolution (#46).
@MainActor
struct ServicesProviderTests {
    @Test func `a recognised URL resolves against the current account`() {
        let account = Account(label: "Work", token: "token")
        let target = ServicesProvider.target(
            for: "https://www.hackerrank.com/x/tests/t1",
            currentAccountID: account.id.uuidString,
            accounts: [account]
        )
        #expect(target?.collection == .tests)
        #expect(target?.accountID == account.id.uuidString)
        #expect(target?.itemID == "t1")
    }

    @Test func `it resolves to nil without an account or without a recognised URL`() {
        // No current account.
        #expect(ServicesProvider.target(
            for: "https://host/x/tests/t1", currentAccountID: nil, accounts: []
        ) == nil)
        // A bare id can't be typed without the chooser, so the Service ignores it.
        let account = Account(label: "Work", token: "token")
        #expect(ServicesProvider.target(
            for: "bare-id", currentAccountID: account.id.uuidString, accounts: [account]
        ) == nil)
        #expect(ServicesProvider.target(
            for: "not-a-url/tests/t1", currentAccountID: account.id.uuidString, accounts: [account]
        ) == nil)
    }

    @Test func `service resolution explains every rejected input`() {
        #expect(ServicesProvider.resolve(
            text: nil,
            currentAccountID: "ACC",
            accounts: []
        ) == .failure(.missingText))
        #expect(ServicesProvider.resolve(
            text: " \n ",
            currentAccountID: "ACC",
            accounts: []
        ) == .failure(.missingText))
        #expect(ServicesProvider.resolve(
            text: "https://www.hackerrank.com/x/tests/t1",
            currentAccountID: nil,
            accounts: []
        ) == .failure(.missingAccount))
        let account = Account(label: "Work", token: "token")
        #expect(ServicesProvider.resolve(
            text: "not a HackerRank URL",
            currentAccountID: account.id.uuidString,
            accounts: [account]
        ) == .failure(.unsupportedURL))
    }

    @Test func `the configured current account host is allowed`() {
        let account = Account(
            label: "Enterprise",
            token: "token",
            baseURL: URL(string: "https://hiring.example.org") ?? Account.defaultBaseURL
        )
        let hosts = ServicesProvider.allowedHosts(
            currentAccountID: account.id.uuidString,
            accounts: [account]
        )

        let target = ServicesProvider.target(
            for: "https://hiring.example.org/x/questions/q1",
            currentAccountID: account.id.uuidString,
            accounts: [account],
            allowedHosts: hosts
        )

        #expect(target?.collection == .questions)
        #expect(target?.itemID == "q1")
    }

    @Test func `a malformed or stale current account is rejected`() {
        let account = Account(label: "Work", token: "token")
        let url = "https://www.hackerrank.com/x/tests/t1"

        #expect(ServicesProvider.resolve(
            text: url,
            currentAccountID: "not-a-uuid",
            accounts: [account]
        ) == .failure(.missingAccount))
        #expect(ServicesProvider.resolve(
            text: url,
            currentAccountID: UUID().uuidString,
            accounts: [account]
        ) == .failure(.missingAccount))
    }
}
