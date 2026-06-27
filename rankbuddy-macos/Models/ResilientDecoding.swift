//
//  ResilientDecoding.swift
//  rankbuddy-macos
//

import Foundation

extension KeyedDecodingContainer {
    /// A forgiving optional decode: returns `nil` for a missing key, an explicit null, **or** a
    /// value of the wrong type, instead of throwing.
    ///
    /// The page envelope decodes its `data` array leniently — any element that throws is dropped
    /// from the list rather than failing the whole page (`HackerRankPage`). That backstop turns a
    /// single over-strict field into silent data loss: a model field marked required but absent or
    /// null on some live records makes every such record vanish (e.g. interviews with no `url`/
    /// `status` yet, or users/candidates with no `email` — #85). Models use this in `init(from:)`
    /// so one odd field defaults instead of dropping the record.
    /// `nonisolated` because models decode off the main actor inside the REST client, while the
    /// target's default actor isolation is `MainActor`.
    nonisolated func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        // `try?` flattens the `T?` from `decodeIfPresent`, so missing key, explicit null, and a
        // type mismatch all collapse to `nil`.
        try? decodeIfPresent(type, forKey: key)
    }
}
