//
//  QuestionEditValidationTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import HackerRankKit
import Testing

@MainActor
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

    @Test func `question creation duration rejects non-numeric text`() {
        #expect(QuestionCreationValidation.isValidDurationText(""))
        #expect(QuestionCreationValidation.isValidDurationText(" 30\n"))
        #expect(!QuestionCreationValidation.isValidDurationText("thirty"))
        #expect(!QuestionCreationValidation.isValidDurationText("-1"))
        #expect(QuestionCreationValidation.isValidDurationText("0"))
        #expect(QuestionCreationValidation.duration(from: " 30\n") == 30)
    }

    @Test func `question creation max score rejects non-numeric text`() {
        #expect(QuestionCreationValidation.isValidMaxScoreText(""))
        #expect(QuestionCreationValidation.isValidMaxScoreText(" 10.5\n"))
        #expect(!QuestionCreationValidation.isValidMaxScoreText("ten"))
        #expect(!QuestionCreationValidation.isValidMaxScoreText("nan"))
        #expect(!QuestionCreationValidation.isValidMaxScoreText("inf"))
        #expect(!QuestionCreationValidation.isValidMaxScoreText("-0.1"))
        #expect(QuestionCreationValidation.isValidMaxScoreText("0"))
        #expect(QuestionCreationValidation.maxScore(from: " 10.5\n") == 10.5)
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
            CodeStubParameter(name: "value", type: "int"),
            CodeStubParameter(name: "Value", type: "string")
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

    @Test func `blank function names normalize to nil`() {
        #expect(nonBlank(" \n\t ") == nil)
        #expect(nonBlank(" solve \n") == "solve")
    }

    @Test func `testcases require meaningful content`() {
        #expect(!TestcaseValidation.hasContent(["", " ", "\n", "", ""], isSample: false))
        #expect(TestcaseValidation.hasContent(["", "1 2", "", "", ""], isSample: false))
        #expect(TestcaseValidation.hasContent(["", "", "", "", ""], isSample: true))
    }

    @Test func `testcase scores reject non-numeric text`() {
        #expect(TestcaseValidation.isValidScore(""))
        #expect(TestcaseValidation.isValidScore(" 10\n"))
        #expect(!TestcaseValidation.isValidScore("ten"))
        #expect(!TestcaseValidation.isValidScore("1.5"))
        #expect(!TestcaseValidation.isValidScore("-1"))
        #expect(TestcaseValidation.isValidScore("0"))
    }

    @Test func `sample testcases require candidate-visible content`() {
        #expect(TestcaseValidation.isValidSample(false, input: "", output: ""))
        #expect(!TestcaseValidation.isValidSample(true, input: " \n", output: ""))
        #expect(TestcaseValidation.isValidSample(true, input: "", output: "42"))
    }
}
