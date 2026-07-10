//
//  StatusBadge.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// A small pill badge used to flag status (e.g. proctoring, plagiarism, integrity).
struct StatusBadge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .frame(width: 11, height: 11)

            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .lineLimit(1)
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
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
