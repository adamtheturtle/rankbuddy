import BuddyAppKit
import Foundation

/// A HackerRank for Work account: a personal access token plus an optional
/// region/base-URL override, identified by a stable per-device `id`.
///
/// Conforms to `StorableAccount` so it can live in `KeychainAccountStore`. It is a
/// `nonisolated` value type so the store's background write queue and the REST client
/// can use it off the main actor under the target's MainActor default isolation.
nonisolated struct Account: StorableAccount, Codable, Identifiable, Hashable {
    /// The default HackerRank base URL, used when no region override is set.
    static var defaultBaseURL: URL {
        // The literal is a known-valid URL; the fallback can never be reached and only
        // exists to avoid a force-unwrap.
        URL(string: "https://www.hackerrank.com") ?? URL(fileURLWithPath: "/")
    }

    /// Stable per-device identifier (the `StorableAccount.accountID`).
    let id: UUID
    /// A user-facing label for the account (e.g. "Work", "EU org").
    var label: String
    /// The HackerRank personal access token. Stored in the Keychain by the account store.
    var token: String
    /// An optional base-URL override for regional HackerRank endpoints.
    var baseURLOverride: String?

    var accountID: UUID {
        id
    }

    /// The effective base URL: the override if it parses, otherwise the default.
    var baseURL: URL {
        if let baseURLOverride, let url = URL(string: baseURLOverride) {
            return url
        }
        return Self.defaultBaseURL
    }

    init(label: String, token: String, baseURLOverride: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.label = label
        self.token = token
        self.baseURLOverride = baseURLOverride
    }

    /// A changed token or base URL points at potentially different data, so the store
    /// fires `onRekeyed` to invalidate caches keyed by this account.
    func pointsAtDifferentBackend(than other: Self) -> Bool {
        token != other.token || baseURLOverride != other.baseURLOverride
    }
}
