//
//  QuestionDetail.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

/// The richer single-question read (`GET /questions/{id}` → `QuestionShow`), carrying fields the
/// list item omits (#105): the MCQ `options` and the correct `answer` (both **sensitive** — the
/// answer is gated behind an explicit reveal in the UI) and the author's `internal_notes`.
///
/// Every field is optional and decoded resiliently, so a 2xx detail response never fails on a
/// shape that varies between question types (a coding question carries no options/answer).
nonisolated struct QuestionDetail: Decodable, Hashable {
    /// The MCQ answer choices, in order.
    let options: [String]
    /// The correct answer (sensitive — revealed only on explicit request).
    let answer: String?
    /// The author's private notes about the question.
    let internalNotes: String?

    enum CodingKeys: String, CodingKey {
        case options
        case answer
        case internalNotes = "internal_notes"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        options = container.lenientDecodeIfPresent([String].self, forKey: .options) ?? []
        answer = container.lenientDecodeIfPresent(String.self, forKey: .answer)
        internalNotes = container.lenientDecodeIfPresent(String.self, forKey: .internalNotes)
    }

    /// Whether the detail adds anything worth showing over the list row, so the UI can avoid
    /// rendering empty sections while the fetch is pending or on a question type with no extras.
    var hasContent: Bool {
        !options.isEmpty || answer?.isEmpty == false || internalNotes?.isEmpty == false
    }
}
