//
//  APIExplorerErrors.swift
//  rankbuddy-macos
//

import HackerRankKit

nonisolated func rankCoverageError(_ error: any Error) -> String {
    if let api = error as? HackerRankError {
        switch api {
        case .http(410, _): return "The audit session expired. Refresh to start again."
        case let .http(status, _): return "HackerRank request failed (HTTP \(status))."
        case .missingAPIKey: return "No HackerRank API token configured."
        case .network: return "Could not reach HackerRank."
        case .decode: return "Could not decode the HackerRank response."
        }
    }
    return "The HackerRank request failed."
}
