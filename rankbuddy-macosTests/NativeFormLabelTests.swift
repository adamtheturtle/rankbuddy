//
//  NativeFormLabelTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

@MainActor
struct NativeFormLabelTests {
    @Test(arguments: [
        ["enable_photo_identification", "Enable Photo Identification"],
        ["enable_ml_plagiarism_analysis", "Enable ML Plagiarism Analysis"],
        ["mcq_correct_score", "MCQ Correct Score"],
        ["id", "ID"],
        ["team_ids", "Team IDs"],
        ["test_result_url", "Test Result URL"],
        ["ide_signals_url", "IDE Signals URL"],
        ["givenName", "Given Name"],
        ["familyName", "Family Name"],
        ["interview_template_id", "Interview Template ID"],
        ["ide_config", "Editor Configuration"]
    ])
    func `field labels preserve words and format complete acronyms`(_ example: [String]) {
        #expect(NativeFormSchema.title(example[0]) == example[1])
    }

    @Test(arguments: [
        ["ide_and_git", "IDE and Git"],
        ["mcq", "Multiple Choice"],
        ["basic_auth", "Basic Authentication"],
        ["bearer_token", "Bearer Token"],
        ["interviewer", "Interviewer"],
        ["3", "3"]
    ])
    func `enum labels are readable while wire values stay separate`(_ example: [String]) {
        #expect(NativeFormSchema.optionTitle(example[0]) == example[1])
    }
}
