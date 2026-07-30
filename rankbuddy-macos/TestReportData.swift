//
//  TestReportData.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// A stable snapshot of everything loaded by the test detail screen for printing and export.
nonisolated struct TestReportData {
    let test: Test
    let shortLoginURL: String?
    let publicLoginURL: String?
    let accessPassword: String?
    let mcqCorrectScore: Double?
    let mcqIncorrectScore: Double?
    let inviters: [TestInviter]

    init(
        test: Test,
        detail: TestDetail? = nil,
        inviters: [TestInviter] = [],
        includeAccessPassword: Bool = false
    ) {
        self.test = test
        shortLoginURL = detail?.shortLoginURL
        publicLoginURL = detail?.publicLoginURL
        accessPassword = includeAccessPassword ? detail?.accessPassword : nil
        mcqCorrectScore = detail?.mcqCorrectScore
        mcqIncorrectScore = detail?.mcqIncorrectScore
        self.inviters = inviters
    }
}

nonisolated extension TestInviter {
    var displayName: String {
        let fullName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !fullName.isEmpty {
            return fullName
        }
        if !email.isEmpty {
            return email
        }
        return id
    }
}
