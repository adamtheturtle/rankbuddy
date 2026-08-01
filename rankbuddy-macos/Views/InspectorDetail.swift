//
//  InspectorDetail.swift
//  rankbuddy-macos
//

import BuddyDesignSystem
import Flow
import HackerRankKit
import SwiftUI

/// A reusable inspector-style header for the detail panes (#54). It shows the item's title in
/// a prominent style above a wrapping row of status chips, mirroring PadBuddy's pad inspector.
/// Placed as the first row inside a grouped `Form`, it presents the title and chips as a
/// distinct header above the labelled sections. The badge row renders only when there are
/// badges; `.listRowBackground(.clear)` keeps the row fill from competing with the title.
struct InspectorHeader: View {
    let title: String
    var badges: [StatusBadge] = []
    /// When set, the title is inline-editable (#95): committing calls this with the new value
    /// and returns whether the write succeeded. `nil` keeps the title static (the default), so
    /// read-only detail panes are unchanged.
    var onRename: ((String) async -> Bool)?
    /// The host increments this to open the inline rename editor from an Edit command/toolbar
    /// button (#95), so Edit enters the same affordance a click on the title would. Ignored when
    /// `onRename` is `nil`; at its default `0` the title behaves as a plain click-to-edit heading.
    var editRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let onRename {
                CommandEditableTitle(title: title, isEditable: true, editRequest: editRequest, onCommit: onRename)
            } else {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !badges.isEmpty {
                HFlow(spacing: 6) {
                    // StatusBadge isn't Identifiable; the order is stable, so the offset is a
                    // safe identity for this short, non-mutating list.
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        badge
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}

extension Test {
    /// Status chips for the inspector header (#54): lifecycle state, scheduling window, and the
    /// notable on/off flags, in rough order of importance. Empty when none apply.
    func inspectorBadges(now: Date) -> [StatusBadge] {
        var badges: [StatusBadge] = []
        if let state, !state.isEmpty {
            badges.append(StatusBadge(
                text: DisplayFormat.enumLabel(state),
                systemImage: "circle.fill",
                tint: .accentColor
            ))
        }
        if let window = windowBadge(now: now) {
            badges.append(window)
        }
        if enableProctoring == true {
            badges.append(StatusBadge(text: "Proctored", systemImage: "eye.fill", tint: .purple))
        }
        if locked == true {
            badges.append(StatusBadge(text: "Locked", systemImage: "lock.fill", tint: .secondary))
        }
        if draft == true {
            badges.append(StatusBadge(text: "Draft", systemImage: "pencil", tint: .orange))
        }
        return badges
    }
}

extension Question {
    /// Status chips for the inspector header (#54): question type and review status.
    var inspectorBadges: [StatusBadge] {
        var badges: [StatusBadge] = []
        if !type.isEmpty {
            badges.append(StatusBadge(text: DisplayFormat.enumLabel(type), systemImage: "doc.text", tint: .accentColor))
        }
        if let status, !status.isEmpty {
            let style: (image: String, tint: Color) = switch status.lowercased() {
            case "active", "approved", "published": ("checkmark.circle.fill", .green)
            case "draft", "pending", "review", "in review": ("clock.fill", .orange)
            case "archived": ("archivebox.fill", .secondary)
            case "rejected": ("xmark.circle.fill", .red)
            default: ("circle.fill", .secondary)
            }
            badges.append(StatusBadge(
                text: DisplayFormat.enumLabel(status),
                systemImage: style.image,
                tint: style.tint
            ))
        }
        return badges
    }
}

extension Interview {
    /// A single status chip for the inspector header (#54), tinted by the interview's state.
    var inspectorBadges: [StatusBadge] {
        let tint: Color = switch status.lowercased() {
        case "completed", "ended": .green
        case "scheduled", "upcoming": .blue
        case "cancelled", "canceled": .red
        default: .secondary
        }
        return [StatusBadge(text: DisplayFormat.enumLabel(status), systemImage: "circle.fill", tint: tint)]
    }
}

extension User {
    /// Status chips for the inspector header (#54): role, account status, and admin scope.
    var inspectorBadges: [StatusBadge] {
        var badges: [StatusBadge] = []
        if let role, !role.isEmpty {
            badges.append(StatusBadge(
                text: DisplayFormat.enumLabel(role),
                systemImage: "person.fill",
                tint: .accentColor
            ))
        }
        if let status, !status.isEmpty {
            let style: (image: String, tint: Color) = switch status.lowercased() {
            case "active", "enabled": ("checkmark.circle.fill", .green)
            case "invited", "pending": ("clock.fill", .orange)
            case "inactive", "deactivated", "disabled", "locked", "suspended":
                ("xmark.circle.fill", .red)
            default: ("circle.fill", .secondary)
            }
            badges.append(StatusBadge(
                text: DisplayFormat.enumLabel(status),
                systemImage: style.image,
                tint: style.tint
            ))
        }
        if companyAdmin == true {
            badges.append(StatusBadge(text: "Company admin", systemImage: "checkmark.seal.fill", tint: .blue))
        } else if teamAdmin == true {
            badges.append(StatusBadge(text: "Team admin", systemImage: "checkmark.seal", tint: .blue))
        }
        return badges
    }
}

extension Team {
    /// Count chips for the inspector header (#54): the team's developer and recruiter sizes,
    /// the figures a recruiter glances at first.
    var inspectorBadges: [StatusBadge] {
        var badges: [StatusBadge] = []
        if let developerCount {
            let plural = developerCount == 1 ? "" : "s"
            badges.append(StatusBadge(
                text: "\(developerCount) developer\(plural)",
                systemImage: "person.2.fill",
                tint: .accentColor
            ))
        }
        if let recruiterCount, recruiterCount > 0 {
            let plural = recruiterCount == 1 ? "" : "s"
            badges.append(StatusBadge(
                text: "\(recruiterCount) recruiter\(plural)",
                systemImage: "person.crop.circle.badge.checkmark",
                tint: .blue
            ))
        }
        return badges
    }
}

extension TestCandidate {
    /// Status chips for the inspector header (#54): attempt and pipeline status, plus any
    /// integrity/plagiarism flag (reuses the existing `integrityBadge`).
    var inspectorBadges: [StatusBadge] {
        var badges: [StatusBadge] = []
        if let attempt = attemptStatusLabel {
            badges.append(StatusBadge(text: attempt, systemImage: "circle.fill", tint: .accentColor))
        }
        if let pipeline = pipelineStatusLabel {
            badges.append(StatusBadge(text: pipeline, systemImage: "arrow.right.circle", tint: .blue))
        }
        if let integrity = integrityBadge {
            badges.append(integrity)
        }
        return badges
    }
}

#Preview("Inspector header") {
    Form {
        InspectorHeader(title: "Live coding: Microservices", badges: [
            StatusBadge(text: "Active", systemImage: "circle.fill", tint: .accentColor),
            StatusBadge(text: "Open", systemImage: "circle.fill", tint: .green),
            StatusBadge(text: "Proctored", systemImage: "eye.fill", tint: .purple)
        ])
        Section("Properties") {
            LabeledContent("Duration", value: "60 min")
            LabeledContent("Languages", value: "Python, Go")
        }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 260)
}
