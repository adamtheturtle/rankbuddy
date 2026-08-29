//
//  TestWriteValidation.swift
//  rankbuddy-macos
//

import Foundation

nonisolated enum TestNameValidation {
    static let maxLength = 255

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= maxLength
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSubmit(_ name: String, currentName: String?) -> Bool {
        let normalizedName = normalized(name)
        guard isValid(normalizedName) else { return false }

        return currentName.map(normalized) != normalizedName
    }
}

nonisolated enum TestAssessmentValidation {
    static let maximumDuration = 1440
    static let maximumCutoffScore = 1_000_000

    static func error(duration: String, cutoffScore: String) -> String? {
        let normalizedDuration = duration.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedDuration.isEmpty,
           Int(normalizedDuration).map({ (1 ... maximumDuration).contains($0) }) != true {
            return "Duration must be a whole number from 1 through 1,440 minutes."
        }

        let normalizedCutoff = cutoffScore.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedCutoff.isEmpty,
           Int(normalizedCutoff).map({ (0 ... maximumCutoffScore).contains($0) }) != true {
            return "Cutoff score must be a whole number from 0 through 1,000,000."
        }
        return nil
    }
}

nonisolated enum TestBooleanEditing {
    static func updateValue(_ value: Bool, changed: Bool) -> Bool? {
        changed ? value : nil
    }
}

nonisolated enum TestDirtyField {
    static func scalar<Value: Equatable>(_ current: Value?, original: Value?) -> Value? {
        current == original ? nil : current
    }

    static func text(_ current: String, original: String?) -> String? {
        current == (original ?? "") ? nil : current
    }

    static func clearableList(_ current: [String]?, original: [String]?) -> [String]? {
        let current = current ?? []
        return current == (original ?? []) ? nil : current
    }

    static func needsNameRebase(edited: String, original: String) -> Bool {
        edited == original
    }
}

nonisolated enum TestListEditing {
    static func values(from text: String) -> [String]? {
        var seen: Set<String> = []
        let values = text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.filter {
            seen.insert($0.folding(options: .caseInsensitive, locale: .current)).inserted
        }
        return values.isEmpty ? nil : values
    }
}
