//
//  InterviewTranscriptFailure.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// A disabled optional feature is an availability state, rather than a failed request to retry.
nonisolated enum InterviewTranscriptFailure: Equatable {
    case transcriptionDisabled
    case requestFailed(String)

    init(error: any Error) {
        if case let HackerRankError.http(400, body) = error,
           let message = HackerRankError.serverMessage(inBody: body),
           message.caseInsensitiveCompare("Interview transcription is not enabled.") == .orderedSame {
            self = .transcriptionDisabled
        } else {
            self = .requestFailed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
