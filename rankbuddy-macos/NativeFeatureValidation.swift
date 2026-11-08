//
//  NativeFeatureValidation.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

enum NativeFeatureValidation {
    static func issue(operationID: String, fields: [String: HackerRankJSONValue]) -> String? {
        switch operationID {
        case "api_create_test", "api_update_test":
            if let name = fields["name"]?.text, !TestNameValidation.isValid(name) {
                return "Test name must contain 1 through 255 characters."
            }
            return TestAssessmentValidation.error(duration: fields["duration"]?.text ?? "",
                                                  cutoffScore: fields["cutoff_score"]?.text ?? "")
                ?? TestScheduleValidation.error(startTime: fields["starttime"]?.text ?? "",
                                                endTime: fields["endtime"]?.text ?? "")

        case "api_create_team", "api_update_team":
            if let name = fields["name"]?.text, !TeamNameValidation.isValid(name) {
                return "Team name must contain 1 through 255 characters."
            }

        case "api_create_user", "api_update_user":
            if let first = fields["firstname"]?.text {
                return UserNameValidation.issue(firstName: first, lastName: fields["lastname"]?.text)
            }
            return UserNameValidation.lastNameIssue(fields["lastname"]?.text)

        case "api_invite_candidate", "api_update_candidate":
            return candidateIssue(fields)

        case "api_create_interview", "api_update_interview":
            return interviewIssue(fields)

        case "api_create_question", "api_update_question":
            return questionIssue(fields)

        default: break
        }
        return nil
    }

    private static func candidateIssue(_ fields: [String: HackerRankJSONValue]) -> String? {
        let from = fields["invite_valid_from"]?.text
        let until = fields["invite_valid_to"]?.text
        let additional = fields["accommodations"]?.object["additional_time"].flatMap { Int($0.text) }
        if !CandidateInviteValidation.isValid(additionalTime: additional) {
            return "Additional time must be from 0 through 1,440 minutes."
        }
        return CandidateInviteValidation.validityTimestampIssue(validFrom: from, validUntil: until)
            ?? CandidateInviteValidation.validityOrderIssue(validFrom: from, validUntil: until)
            ?? CandidateInviteValidation.textIssue(.init(
                fullName: fields["full_name"]?.text, tags: strings(fields["tags"]),
                evaluatorEmail: fields["evaluator_email"]?.text, emailSubject: fields["subject"]?.text,
                emailMessage: fields["message"]?.text, atsCandidateID: nil, atsRequisitionID: nil
            ))
    }

    private static func interviewIssue(_ fields: [String: HackerRankJSONValue]) -> String? {
        if let issue = InterviewScheduleValidation.textIssue(
            title: fields["title"]?.text ?? "", candidateEmail: fields["candidate"]?.object["email"]?.text,
            notes: fields["notes"]?.text
        ) {
            return issue
        }
        if let start = fields["from"]?.text,
           let date = DisplayFormat.parseDate(start),
           let issue = InterviewScheduleValidation.dateIssue(start: date) {
            return issue
        }
        return TestScheduleValidation.error(startTime: fields["from"]?.text ?? "",
                                            endTime: fields["to"]?.text ?? "")
    }

    private static func questionIssue(_ fields: [String: HackerRankJSONValue]) -> String? {
        if let name = fields["name"]?.text, let issue = QuestionCreationValidation.nameIssue(name) {
            return issue
        }
        if let text = fields["recommended_duration"]?.text,
           !QuestionCreationValidation.isValidDurationText(text)
           || !QuestionEditValidation.isValidRecommendedDuration(QuestionCreationValidation.duration(from: text)) {
            return "Recommended duration must be from 0 through 1,440 minutes."
        }
        return QuestionAuthoringValidation.boundsIssue(problemStatement: fields["problem_statement"]?.text ?? "",
                                                       languages: strings(fields["languages"]),
                                                       tags: strings(fields["tags"]))
    }

    private static func strings(_ value: HackerRankJSONValue?) -> [String]? {
        value.map { $0.array.map(\.text) }
    }
}
