//
//  CandidateSearchDetailView.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// A person-first view of the organisation-wide search response, with readable attempt history.
struct CandidateSearchDetailView: View {
    let record: NativeBusinessRecord

    private var candidate: CandidateSearchPresentation {
        CandidateSearchPresentation(value: record.value)
    }

    private var hasProfile: Bool {
        candidate.identifier != nil || candidate.text("created_at") != nil || candidate.text("updated_at") != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(candidate.title).font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if candidate.name != nil, let email = candidate.email {
                        Text(email).foregroundStyle(.secondary)
                    }
                }
                Divider()
                if hasProfile {
                    profile
                    Divider()
                }
                attempts
                if !candidate.additionalFields.isEmpty {
                    DisclosureGroup("Additional Details") {
                        NativeRecordContent(value: .object(candidate.additionalFields))
                    }
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile").font(.headline).accessibilityAddTraits(.isHeader)
            CandidateSearchFact("Created", candidate.date("created_at"))
            CandidateSearchFact("Updated", candidate.date("updated_at"))
            CandidateSearchFact("Candidate ID", candidate.identifier)
        }
    }

    private var attempts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Attempts (\(candidate.attempts.count))").font(.headline).accessibilityAddTraits(.isHeader)
            if candidate.attempts.isEmpty {
                Text("No attempts were returned for this candidate.").foregroundStyle(.secondary)
            }
            ForEach(Array(candidate.attempts.enumerated()), id: \.offset) { index, value in
                if index > 0 {
                    Divider()
                }
                CandidateSearchAttemptView(attempt: CandidateAttemptPresentation(value: value, index: index))
            }
        }
    }
}

private struct CandidateSearchAttemptView: View {
    let attempt: CandidateAttemptPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(attempt.title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            CandidateSearchFact("Started", attempt.started)
            CandidateSearchFact("Completed", attempt.completed)
            CandidateSearchFact("Score", attempt.number("score"))
            CandidateSearchFact("Percentage", attempt.number("percentage_score").map { "\($0)%" })
            CandidateSearchFact("Attempt ID", attempt.value.object["attempt_id"]?.text)
            CandidateSearchFact("Test ID", attempt.namedTestID)
            if let url = attempt.reportURL {
                Link("View Report", destination: url)
                    .accessibilityLabel("View report for \(attempt.title)")
            }
            if !attempt.additionalFields.isEmpty {
                DisclosureGroup("Additional Attempt Details") {
                    NativeRecordContent(value: .object(attempt.additionalFields))
                }
            }
        }
    }
}

private struct CandidateSearchFact: View {
    let label: String
    let value: String?

    init(_ label: String, _ value: String?) {
        self.label = label
        self.value = value
    }

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
            .accessibilityIdentifier("candidate-fact-\(label)")
            .accessibilityAddTraits(.isStaticText)
        }
    }
}
