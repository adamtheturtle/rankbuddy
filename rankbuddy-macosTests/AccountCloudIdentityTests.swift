//
//  AccountCloudIdentityTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct AccountCloudIdentityTests {
    @Test func `cloud identity is stable across devices without exposing owner data`() {
        let first = Account(label: "Work", token: "one", userEmail: " Person@Example.com ")
        let second = Account(label: "Renamed", token: "two", userEmail: "person@example.com")

        #expect(first.cloudIdentity == second.cloudIdentity)
        #expect(!first.cloudIdentity.contains("person"))
        #expect(first.cloudIdentity.count == 64)
    }

    @Test func `cloud identity distinguishes owners and servers`() {
        let first = Account(label: "Work", token: "one", userEmail: "one@example.com")
        let otherOwner = Account(label: "Work", token: "two", userEmail: "two@example.com")
        let otherServer = Account(
            label: "Work",
            token: "three",
            baseURLOverride: "https://eu.example.com",
            userEmail: "one@example.com"
        )

        #expect(first.cloudIdentity != otherOwner.cloudIdentity)
        #expect(first.cloudIdentity != otherServer.cloudIdentity)
    }
}
