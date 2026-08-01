//
//  UserNameValidation.swift
//  rankbuddy-macos
//

import Foundation

nonisolated enum UserNameValidation {
    static let maxLength = 255

    static func firstNameIssue(_ value: String) -> String? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "First name is required."
        }

        return value.count > maxLength ? "First name can be at most \(maxLength) characters." : nil
    }

    static func lastNameIssue(_ value: String?) -> String? {
        guard let value, value.count > maxLength else { return nil }

        return "Last name can be at most \(maxLength) characters."
    }

    static func issue(firstName: String, lastName: String?) -> String? {
        if let issue = firstNameIssue(firstName) {
            return issue
        }
        if let issue = lastNameIssue(lastName) {
            return issue
        }
        return nil
    }
}
