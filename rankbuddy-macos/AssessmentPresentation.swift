//
//  AssessmentPresentation.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

extension Test {
    /// Section names describe groups of questions, not the assessment's type.
    var presentationTypes: [String] {
        guard let type = type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty else { return [] }

        return [DisplayFormat.enumLabel(type)]
    }
}

extension TestSection {
    func presentationTitle(index: Int) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty, name.caseInsensitiveCompare("Untitled") != .orderedSame {
            return name
        }
        return "Section \(index + 1)"
    }
}
