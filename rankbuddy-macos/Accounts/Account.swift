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
    /// The email of the user this token belongs to (#72), entered in the editor. Identifies
    /// "who am I" for this account, enabling owned-by-me / assigned-to-me filtering. Optional
    /// and decoded with `decodeIfPresent`, so accounts saved before this field stay valid.
    var userEmail: String?
    /// An SF Symbol name distinguishing this account in the switcher/sidebar (#64). Optional;
    /// `nil` falls back to a generic person icon. `decodeIfPresent`, so older accounts decode.
    var iconSymbol: String?
    /// A "#RRGGBB" tint for this account's icon (#64). Optional; `nil` uses the app accent.
    var tintHex: String?

    var accountID: UUID {
        id
    }

    /// The reserved token that marks the in-process demo account (mirrors PadBuddy's
    /// "demo" mock key). Not a valid HackerRank token, so a real account never collides.
    static let demoToken = "demo"
    /// The reserved token for the bad-key demo: the mock answers it with a 401, so the
    /// authentication-failure UI can be shown without a real (revoked) token.
    static let badKeyDemoToken = "demo-bad-key"

    /// Whether this account is backed by the in-process demo mock rather than the live API
    /// (mirrors PadBuddy's per-account demo model). Derived from a reserved demo token, so
    /// it survives a Keychain round-trip for free and needs no extra persisted field.
    var isMock: Bool {
        token == Self.demoToken || token == Self.badKeyDemoToken
    }

    /// A demo account backed by the bundled mock server (#10), selectable like a real
    /// account. Its reserved token routes it to the fixtures; the mock never checks it.
    static var demo: Self {
        // A fixed id keeps the demo's restored section/selection stable across launches.
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000DEAD") ?? UUID()
        return Self(label: "Demo (HackerRank)", token: demoToken, id: id)
    }

    /// A demo account whose token the mock rejects with a 401 — exercises the
    /// authentication-failure state with a selectable account rather than a global flag.
    static var badKeyDemo: Self {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000BADC0DE5") ?? UUID()
        return Self(label: "Demo (bad token)", token: badKeyDemoToken, id: id)
    }

    /// The effective base URL: the override if it parses, otherwise the default.
    var baseURL: URL {
        if let baseURLOverride, let url = URL(string: baseURLOverride) {
            return url
        }
        return Self.defaultBaseURL
    }

    init(
        label: String,
        token: String,
        baseURLOverride: String? = nil,
        userEmail: String? = nil,
        iconSymbol: String? = nil,
        tintHex: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.label = label
        self.token = token
        self.baseURLOverride = baseURLOverride
        self.userEmail = userEmail
        self.iconSymbol = iconSymbol
        self.tintHex = tintHex
    }

    /// A changed token or base URL points at potentially different data, so the store
    /// fires `onRekeyed` to invalidate caches keyed by this account.
    func pointsAtDifferentBackend(than other: Self) -> Bool {
        token != other.token || baseURLOverride != other.baseURLOverride
    }
}
