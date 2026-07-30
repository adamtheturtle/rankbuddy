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

    @Test func `custom code stubs require visible source`() {
        #expect(!CodeStubValidation.hasSource(""))
        #expect(!CodeStubValidation.hasSource(" \n\t "))
        #expect(CodeStubValidation.hasSource("  return value\n"))
    }

    @Test func `custom code stub languages reject every blank form`() {
        #expect(CodeStubValidation.normalizedLanguage(" \n\t ") == nil)
        #expect(CodeStubValidation.normalizedLanguage("\npython \n") == "python")
    }

    @Test func `generated stub parameter names must be unique`() {
        let parameters = [
            GenerateCodeStubsBody.Parameter(name: "value", type: "int"),
            GenerateCodeStubsBody.Parameter(name: "Value", type: "string")
        ]
        #expect(CodeStubValidation.duplicateParameterName(in: parameters) == "Value")
        #expect(CodeStubValidation.duplicateParameterName(in: [parameters[0]]) == nil)
    }

    @Test func `generated stub parameters reject malformed entries`() {
        #expect(CodeStubValidation.malformedParameter(in: "") == nil)
        #expect(CodeStubValidation.malformedParameter(in: "counts: int[], target") == "target")
        #expect(CodeStubValidation.malformedParameter(in: "name: ") == "name:")
        #expect(CodeStubValidation.malformedParameter(in: "counts: int[], target: int") == nil)
    }
}
