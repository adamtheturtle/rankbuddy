//
//  QuestionEditValidationTests.swift
//  rankbuddy-macosTests
//

import HackerRankKit
@testable import rankbuddy_macos
import Testing

@MainActor
struct QuestionEditValidationTests {
    @Test func `system prompts count Unicode scalars and accept empty text`() {
        #expect(QuestionEditValidation.systemPromptIssue("") == nil)
        #expect(QuestionEditValidation.systemPromptIssue(String(repeating: "🐢", count: 15000)) == nil)
        #expect(QuestionEditValidation.systemPromptIssue(String(repeating: "x", count: 15001)) != nil)
    }

    @Test func `question creation names respect the API limit`() {
        #expect(QuestionCreationValidation.nameIssue(String(repeating: "x", count: 255)) == nil)
        #expect(QuestionCreationValidation.nameIssue(String(repeating: "x", count: 256)) != nil)
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

    @Test func `generated stubs require portable identifiers`() {
        for accepted in ["solve", "_value", "value2"] {
            #expect(CodeStubValidation.isPortableIdentifier(accepted))
        }
        for rejected in ["", "2value", "two words", "value-name", "résultat"] {
            #expect(!CodeStubValidation.isPortableIdentifier(rejected))
        }

        let parameters = [CodeStubParameter(name: "bad name", type: "int")]
        #expect(CodeStubValidation.invalidParameterIdentifier(in: parameters) == "bad name")
    }

    @Test func `generated stub parameters reject malformed entries`() {
        #expect(CodeStubValidation.malformedParameter(in: "") == nil)
        #expect(CodeStubValidation.malformedParameter(in: "counts: int[], target") == "target")
        #expect(CodeStubValidation.malformedParameter(in: "name: ") == "name:")
        #expect(CodeStubValidation.malformedParameter(in: "counts: int[], target: int") == nil)
    }

    @Test func `generated stub parameters trim newlines from request values`() {
        let parameters = CodeStubValidation.parsedParameters(in: "\n name\n: \nint\n")

        #expect(parameters?.first?.name == "name")
        #expect(parameters?.first?.type == "int")
    }

    @Test func `code stub requests enforce product bounds`() {
        let oversized = String(repeating: "x", count: CodeStubValidation.maxFieldLength + 1)
        let tooManyParameters = Array(
            repeating: CodeStubParameter(name: "value", type: "int"),
            count: CodeStubValidation.maxParameters + 1
        )
        let tooManyLanguages = Array(repeating: "swift", count: CodeStubValidation.maxLanguages + 1)

        #expect(CodeStubValidation.generationBoundsIssue(
            functionName: oversized,
            returnType: nil,
            parameters: nil,
            languages: nil
        ) != nil)
        #expect(CodeStubValidation.generationBoundsIssue(
            functionName: "solve",
            returnType: nil,
            parameters: tooManyParameters,
            languages: nil
        ) != nil)
        #expect(CodeStubValidation.generationBoundsIssue(
            functionName: "solve",
            returnType: nil,
            parameters: nil,
            languages: tooManyLanguages
        ) != nil)
        #expect(CodeStubValidation.customStubBoundsIssue(
            language: "swift",
            code: String(repeating: "x", count: CodeStubValidation.maxSourceLength + 1)
        ) != nil)
        #expect(CodeStubValidation.customStubBoundsIssue(
            language: "swift",
            code: String(repeating: "x", count: CodeStubValidation.maxSourceLength)
        ) == nil)
    }

    @Test func `blank function names normalize to nil`() {
        #expect(nonBlank(" \n\t ") == nil)
        #expect(nonBlank(" solve \n") == "solve")
    }

    @Test func `cases require meaningful content`() {
        #expect(!TestcaseValidation.hasContent(input: "", output: " \n"))
        #expect(TestcaseValidation.hasContent(input: "1 2", output: ""))
        #expect(TestcaseValidation.hasContent(input: "", output: "42"))
    }

    @Test func `question authoring payloads enforce size and list bounds`() {
        let oversized = String(repeating: "x", count: QuestionAuthoringValidation.maxProblemStatementLength + 1)
        let tooMany = Array(repeating: "swift", count: QuestionAuthoringValidation.maxListCount + 1)

        #expect(QuestionAuthoringValidation.boundsIssue(
            problemStatement: oversized,
            languages: nil,
            tags: nil
        ) != nil)
        #expect(QuestionAuthoringValidation.boundsIssue(
            problemStatement: "",
            languages: tooMany,
            tags: nil
        ) != nil)
        #expect(TestcaseValidation.boundsIssue(
            name: String(repeating: "x", count: TestcaseValidation.maxNameLength + 1),
            input: "",
            output: "",
            explanation: ""
        ) != nil)
        #expect(TestcaseValidation.boundsIssue(
            name: "sample",
            input: String(repeating: "x", count: TestcaseValidation.maxDataLength),
            output: "",
            explanation: ""
        ) == nil)
    }

    @Test func `case scores reject non-numeric text`() {
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
