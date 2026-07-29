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

    @Test func `recommended duration is bounded to one day`() {
        #expect(QuestionEditValidation.isValidRecommendedDuration(nil))
        #expect(QuestionEditValidation.isValidRecommendedDuration(0))
        #expect(QuestionEditValidation.isValidRecommendedDuration(1440))
        #expect(!QuestionEditValidation.isValidRecommendedDuration(-1))
        #expect(!QuestionEditValidation.isValidRecommendedDuration(1441))
    }

    @Test func `comma-separated values deduplicate without losing first spelling`() {
        #expect(splitList("swift, Swift, SWIFT, résumé, resume") == ["swift", "résumé"])
        #expect(splitList(" , ") == nil)
    }
}
