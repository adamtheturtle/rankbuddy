//
//  HackerRankError.swift
//  rankbuddy-macos
//

import Foundation
import PaginatedRESTClient

/// Errors surfaced by `HackerRankClient`, mapped from the transport layer.
///
/// `nonisolated` so it can be thrown and inspected off the main actor by the
/// transport's pagination pipeline.
nonisolated enum HackerRankError: LocalizedError {
    /// No personal access token was configured for the account.
    case missingAPIKey
    /// The API returned a non-2xx HTTP status with the given response body.
    case http(status: Int, body: String)
    /// A response could not be decoded; the associated value describes where.
    case decoding(String)
    /// A transport-level failure (offline, timeout, unreachable host).
    case network(URLError)

    var errorDescription: String? {
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

        case .decoding:
            "The response from HackerRank could not be read."

        case let .network(error):
            "Could not reach HackerRank: \(error.localizedDescription)"
        }
    }
}

/// Maps the generic transport's failures onto `HackerRankError` and decides which are
/// transient (worth retrying). `nonisolated` because the transport calls it off the
/// main actor.
nonisolated struct HackerRankErrorMapping: RESTTransportErrorMapping {
    func missingAPIKey() -> Error {
        HackerRankError.missingAPIKey
    }

    func http(status: Int, body: String) -> Error {
        HackerRankError.http(status: status, body: body)
    }

    func decode(_ detail: String) -> Error {
        HackerRankError.decoding(detail)
    }

    func network(_ error: URLError) -> Error {
        HackerRankError.network(error)
    }

    /// Retry on 429 and 5xx (the server asked us to back off or had a transient fault)
    /// and on the recoverable transport errors. Everything else — 4xx auth/validation,
    /// decoding — is permanent and surfaces immediately.
    func isTransient(_ error: Error) -> Bool {
        guard let error = error as? HackerRankError else { return false }

        switch error {
        case let .http(status, _):
            return status == 429 || (500 ... 599).contains(status)

        case let .network(urlError):
            let transientCodes: Set<URLError.Code> = [
                .timedOut,
                .networkConnectionLost,
                .cannotConnectToHost,
                .notConnectedToInternet,
                .dnsLookupFailed
            ]
            return transientCodes.contains(urlError.code)

        case .missingAPIKey, .decoding:
            return false
        }
    }
}
