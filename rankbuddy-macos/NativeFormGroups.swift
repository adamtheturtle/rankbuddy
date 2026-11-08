//
//  NativeFormGroups.swift
//  rankbuddy-macos
//

import Foundation

enum NativeFormGroups {
    static let names = ["Basics", "Schedule", "Content", "Questions and Scoring", "Permissions",
                        "Assessment Integrity", "Invitations and Results", "Editor", "Additional Settings"]

    static func group(for name: String) -> String {
        if ["name", "title", "email", "full_name", "firstname", "lastname", "country", "phone", "role", "type",
            "userName", "diplayName"].contains(name) {
            return "Basics"
        }
        if ["from", "to", "starttime", "endtime", "duration", "recommended_duration", "invite_valid_from",
            "invite_valid_to", "accommodations"].contains(name) {
            return "Schedule"
        }
        if [
            "problem_statement",
            "internal_notes",
            "custom_system_prompt",
            "instructions",
            "options",
            "answer",
            "content"
        ].contains(name) {
            return "Content"
        }
        if ["questions", "question_ids", "scorecard_id", "cutoff_score", "mcq_correct_score", "mcq_incorrect_score",
            "shuffle_questions", "role_ids", "experience"].contains(name) {
            return "Questions and Scoring"
        }
        if name.contains("permission") || ["teams", "test_admins", "company_admin", "team_admin", "locked", "draft",
                                           "license", "recruiter_cap", "developer_cap", "active"].contains(name) {
            return "Permissions"
        }
        if name.contains("proctoring") || name.contains("secure") || name.contains("plagiarism")
            || name.contains("identification") {
            return "Assessment Integrity"
        }
        if name.contains("email") || name.contains("url") || name.contains("webhook") || name.contains("force")
            || ["template", "subject", "message", "accept_result_updates", "send_email"].contains(name) {
            return "Invitations and Results"
        }
        if ["languages", "functionName", "functionParams", "functionReturn", "allowedLanguages", "templates",
            "ide_config", "hide_compile_test", "hide_template"].contains(name) {
            return "Editor"
        }
        return "Additional Settings"
    }
}
