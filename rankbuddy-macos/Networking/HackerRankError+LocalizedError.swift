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

        case let .http(status, body):
            switch status {
            case 401, 403:
                "The token was rejected. Check that it is a valid HackerRank for Work personal access token."
            case 429:
                "HackerRank is rate-limiting requests. Please try again shortly."
            case 404:
                "The requested HackerRank resource was not found."
            case 0:
                // Status 0 is the client's own "no request was made" marker (an unusable
                // URL or a pagination safety stop), not a server response; "HTTP 0"
                // would be nonsense to a user.
                "A HackerRank request could not be completed. Please try again."
            default:
                if let detail = Self.serverMessage(inBody: body) {
                    "HackerRank rejected the request (HTTP \(status)): \(detail)"
                } else {
                    "HackerRank returned an unexpected error (HTTP \(status))."
                }
            }

        case .decode:
            "The response from HackerRank could not be read."

        case let .network(error):
            "Could not reach HackerRank: \(error.localizedDescription)"
        }
    }

    /// Pulls the human-readable explanation out of a HackerRank error body, so a 400 can say
    /// what was actually wrong (for example "Email has already been taken") instead of only the
    /// status code. HackerRank error bodies are JSON in a few shapes: a top-level "message" or
    /// "error" string, an "errors" array of strings or of objects with a "message", or a
    /// Rails-style "errors" map of field name to problems.
    private static func serverMessage(inBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var messages: [String] = []
        for key in ["message", "error"] {
            if let text = object[key] as? String { messages.append(text) }
        }
        messages.append(contentsOf: errorFieldMessages(object["errors"]))

        let joined = messages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !joined.isEmpty else { return nil }

        return joined.hasSuffix(".") ? joined : joined + "."
    }

    private static func errorFieldMessages(_ errors: Any?) -> [String] {
        switch errors {
        case let strings as [String]:
            strings

        case let objects as [[String: Any]]:
            objects.compactMap { $0["message"] as? String }

        case let fields as [String: Any]:
            fields.sorted { $0.key < $1.key }.flatMap { field, value -> [String] in
                let problems = (value as? [String]) ?? (value as? String).map { [$0] } ?? []
                return problems.map { "\(field.capitalized) \($0)" }
            }

        default:
            []
        }
    }
}
