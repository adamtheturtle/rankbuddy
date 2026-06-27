//
//  StatusBadge.swift
//  rankbuddy-macos
//

import SwiftUI

/// A small pill badge used to flag status (e.g. proctoring, plagiarism, integrity).
struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

extension TestCandidate {
    /// An integrity/plagiarism flag to surface in the UI, if the candidate has one (#14).
    var integrityBadge: StatusBadge? {
        if plagiarismStatus == true {
            return StatusBadge(text: "Plagiarism", systemImage: "exclamationmark.shield.fill", tint: .red)
        }
        switch integrityStatus?.lowercased() {
        case "review", "flagged":
            return StatusBadge(text: "Review", systemImage: "exclamationmark.triangle.fill", tint: .orange)
        case "clean":
            return StatusBadge(text: "Clean", systemImage: "checkmark.shield.fill", tint: .green)
        default:
            return nil
        }
    }
}
