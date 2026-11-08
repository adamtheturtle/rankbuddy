//
//  TestWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// Whether the test editor is creating a new test or editing an existing assessment.
enum TestEditorMode {
    case create
    case edit(Test)
}

/// A sheet that creates or edits a test, including the assessment fields supported by
/// HackerRankKit's typed write options (#137).
struct TestEditorSheet: View {
    let account: Account
    let mode: TestEditorMode
    var onSaved: () -> Void
    var body: some View {
        switch mode {
        case .create:
            NativeFeatureFormSheet(
                title: "New Test",
                operationID: "api_create_test",
                account: account,
                onSaved: onSaved
            )

        case let .edit(test):
            NativeFeatureFormSheet(title: "Edit Test", operationID: "api_update_test", account: account,
                                   path: ["id": test.id], onSaved: onSaved)
        }
    }
}

nonisolated enum TestScheduleValidation {
    static func error(startTime: String, endTime: String) -> String? {
        let start = normalizedDate(startTime)
        let end = normalizedDate(endTime)
        if !startTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, start == nil {
            return "Start time must be an ISO-8601 timestamp."
        }
        if !endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, end == nil {
            return "End time must be an ISO-8601 timestamp."
        }
        if let start, let end, end <= start {
            return "End time must be after start time."
        }
        return nil
    }

    private static func normalizedDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

#Preview("New Test (demo)") {
    TestEditorSheet(account: .demo, mode: .create) {}
}
