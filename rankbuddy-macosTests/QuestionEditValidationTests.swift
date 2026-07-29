//
//  QuestionEditValidationTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct QuestionEditValidationTests {
    @Test func `max score rejects non-finite numbers`() {
        #expect(QuestionEditValidation.maxScore(from: "10.5") == 10.5)
        #expect(QuestionEditValidation.maxScore(from: "nan") == nil)
        #expect(QuestionEditValidation.maxScore(from: "inf") == nil)
        #expect(QuestionEditValidation.maxScore(from: "-inf") == nil)
        #expect(QuestionEditValidation.maxScore(from: "-0.1") == nil)
        #expect(QuestionEditValidation.maxScore(from: "0") == 0)
    }
}
