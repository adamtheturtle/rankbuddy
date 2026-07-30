//
//  CandidateDetailTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

struct CandidateDetailTests {
    @Test func `request identity includes account test and candidate`() {
        let accountA = UUID()
        let accountB = UUID()
        let original = CandidateDetailRequestIdentity(accountID: accountA, testID: "t1", candidateID: "c1")

        #expect(original != CandidateDetailRequestIdentity(accountID: accountB, testID: "t1", candidateID: "c1"))
        #expect(original != CandidateDetailRequestIdentity(accountID: accountA, testID: "t2", candidateID: "c1"))
        #expect(original != CandidateDetailRequestIdentity(accountID: accountA, testID: "t1", candidateID: "c2"))
        #expect(original == CandidateDetailRequestIdentity(accountID: accountA, testID: "t1", candidateID: "c1"))
    }
}
