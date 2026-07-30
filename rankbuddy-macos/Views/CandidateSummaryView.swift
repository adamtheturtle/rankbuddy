//
//  CandidateSummaryView.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// An opt-in "Summarise" affordance on the candidate detail (#93): a single button that asks the
/// on-device model for a plain-language synthesis of the candidate's signals, shows progress,
/// and renders the result inline. Hidden entirely when the model is unavailable or there is
/// nothing to summarise, so it degrades gracefully. Nothing is persisted or auto-run.
struct CandidateSummaryView: View {
    let candidate: TestCandidate

    @State private var state: SummaryState = .idle

    private enum SummaryState: Equatable {
        case idle
        case loading
        case summary(String)
        case policyViolation
        case failed
    }

    var body: some View {
        // Only offer the feature when the model is ready and there are facts to work from.
        if CandidateSummarizer.isAvailable, CandidateBrief.prompt(for: candidate) != nil {
            Section("AI Summary") {
                switch state {
                case .idle:
                    summariseButton

                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Summarising on device…").foregroundStyle(.secondary)
                    }

                case let .summary(text):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        regenerateButton
                    }

                case .policyViolation:
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "The generated text was hidden because it included a hiring recommendation.",
                            systemImage: "exclamationmark.shield"
                        )
                        .foregroundStyle(.secondary)
                        regenerateButton
                    }

                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Couldn't generate a summary.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        summariseButton
                    }
                }
            }
        }
    }

    private var summariseButton: some View {
        Button {
            Task { await run() }
        } label: {
            Label("Summarise", systemImage: "sparkles")
        }
        .help("Generate a plain-language summary on this device")
    }

    private var regenerateButton: some View {
        Button {
            Task { await run() }
        } label: {
            Label("Regenerate", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private func run() async {
        state = .loading
        switch await CandidateSummarizer.summarize(candidate) {
        case let .summary(text):
            state = .summary(text)
        case .policyViolation:
            state = .policyViolation
        case .noData, .unavailable, .failed:
            state = .failed
        }
    }
}
