//
//  TestDetail.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

/// The richer single-test read (`GET /tests/{id}` → `TestsShow`), carrying fields the list item
/// omits (#105): the candidate login links, the (sensitive) shared access password — gated
/// behind an explicit reveal in the UI — and the MCQ scoring.
///
/// Every field is optional and decoded resiliently, so a 2xx detail response never fails on a
/// shape that varies between tests.
nonisolated struct TestDetail: Decodable, Hashable {
    /// A short candidate login URL.
    let shortLoginURL: String?
    /// The public candidate login URL.
    let publicLoginURL: String?
    /// The shared access password for the test (HackerRank's "master password"; sensitive —
    /// revealed only on explicit request).
    let accessPassword: String?
    /// Score awarded for a correct MCQ answer.
    let mcqCorrectScore: Double?
    /// Score deducted for an incorrect MCQ answer.
    let mcqIncorrectScore: Double?

    enum CodingKeys: String, CodingKey {
        case shortLoginURL = "short_login_url"
        case publicLoginURL = "public_login_url"
        case accessPassword = "master_password"
        case mcqCorrectScore = "mcq_correct_score"
        case mcqIncorrectScore = "mcq_incorrect_score"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shortLoginURL = try? container.decodeIfPresent(String.self, forKey: .shortLoginURL)
        publicLoginURL = try? container.decodeIfPresent(String.self, forKey: .publicLoginURL)
        accessPassword = try? container.decodeIfPresent(String.self, forKey: .accessPassword)
        mcqCorrectScore = try? container.decodeIfPresent(Double.self, forKey: .mcqCorrectScore)
        mcqIncorrectScore = try? container.decodeIfPresent(Double.self, forKey: .mcqIncorrectScore)
    }

    /// Whether the detail adds a login link worth a dedicated section, so the UI can avoid an
    /// empty "Access" group while the fetch is pending or on a test with no links.
    var hasAccess: Bool {
        shortLoginURL?.isEmpty == false || publicLoginURL?.isEmpty == false || accessPassword?.isEmpty == false
    }

    /// Whether MCQ scoring was reported, so that section only shows when present.
    var hasScoring: Bool {
        mcqCorrectScore != nil || mcqIncorrectScore != nil
    }
}
