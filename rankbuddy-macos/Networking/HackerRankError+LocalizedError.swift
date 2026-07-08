//
//  HackerRankError+LocalizedError.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// `HackerRankKit` keeps `HackerRankError` presentation-free (it only conforms to
/// `CustomStringConvertible`). The app supplies the localized, user-facing copy by
/// conforming it to `LocalizedError` here, so `(error as? LocalizedError)?.errorDescription`
/// keeps working across the write flows and the account-health banner.
extension HackerRankError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No HackerRank token is configured for this account."

        case let .http(status, _):
            switch status {
            case 401, 403:
                "The token was rejected. Check that it is a valid HackerRank for Work personal access token."
            case 429:
                "HackerRank is rate-limiting requests. Please try again shortly."
            case 404:
                "The requested HackerRank resource was not found."
            default:
                "HackerRank returned an unexpected error (HTTP \(status))."
            }

        case .decode:
            "The response from HackerRank could not be read."

        case let .network(error):
            "Could not reach HackerRank: \(error.localizedDescription)"
        }
    }
}
