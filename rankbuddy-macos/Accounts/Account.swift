//
//  Account.swift
//  rankbuddy-macos
//

import BuddyAppKit
import CryptoKit
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
    static let maximumLabelLength = 100
    /// The HackerRank personal access token. Stored in the Keychain by the account store.
    var token: String
    /// An optional base-URL override for regional HackerRank endpoints.
    var baseURLOverride: String?
    /// The email of the user this token belongs to (#72), cached from token validation. Identifies
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

    /// User-facing descriptions are compared case-insensitively after trimming so account
    /// selectors never contain choices that look identical.
    static func labelsConflict(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        return !left.isEmpty && left.localizedCaseInsensitiveCompare(right) == .orderedSame
    }

    static func limitedLabel(_ label: String) -> String {
        String(label.prefix(maximumLabelLength))
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

    /// Whether this is the intentionally rejected demo token.
    var isBadKeyDemo: Bool {
        token == Self.badKeyDemoToken
    }

    /// A sandbox demo the user can summon by typing a magic word into the account
    /// editor's token field: `demo` adds mock data, `baddemo` adds the rejected-token demo.
    enum DemoMagicKey {
        case mockData
        case badKey

        init?(typedToken: String) {
            switch typedToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "demo": self = .mockData
            case "baddemo": self = .badKey
            default: return nil
            }
        }
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

    /// The parsed base URL override: a non-empty HTTPS URL with a host.
    var parsedBaseURLOverride: URL? {
        let trimmed = baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }

        return url
    }

    /// Whether a non-empty override is malformed. Such a value must not fall back silently:
    /// validation would send this token to the wrong HackerRank host.
    var hasMalformedBaseURLOverride: Bool {
        let trimmed = baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty && parsedBaseURLOverride == nil
    }

    /// The effective base URL: the parsed override if present, otherwise the default.
    var baseURL: URL {
        parsedBaseURLOverride ?? Self.defaultBaseURL
    }

    /// A canonical server identity for duplicate detection and cache invalidation.
    var serverIdentity: String {
        Self.serverIdentity(of: baseURL)
    }

    /// A deterministic, non-secret cross-device identity for synchronizing account-scoped user
    /// state without putting the token or email itself in iCloud. The validated current-user email
    /// distinguishes accounts on the same HackerRank host; legacy accounts fall back to their
    /// normalized label until identity discovery succeeds.
    var cloudIdentity: String {
        let owner = userEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fallback = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = "\(serverIdentity)|\(owner?.isEmpty == false ? owner ?? fallback : fallback)"
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func serverIdentity(of url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if let port = components.port,
           (components.scheme == "https" && port == 443) || (components.scheme == "http" && port == 80) {
            components.port = nil
        }
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
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
        self.label = Self.limitedLabel(label)
        self.token = token
        self.baseURLOverride = baseURLOverride
        self.userEmail = userEmail
        self.iconSymbol = iconSymbol
        self.tintHex = tintHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, token, baseURLOverride, userEmail, iconSymbol, tintHex
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        label = try Self.limitedLabel(values.decode(String.self, forKey: .label))
        token = try values.decode(String.self, forKey: .token)
        baseURLOverride = try values.decodeIfPresent(String.self, forKey: .baseURLOverride)
        userEmail = try values.decodeIfPresent(String.self, forKey: .userEmail)
        iconSymbol = try values.decodeIfPresent(String.self, forKey: .iconSymbol)
        tintHex = try values.decodeIfPresent(String.self, forKey: .tintHex)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(Self.limitedLabel(label), forKey: .label)
        try values.encode(token, forKey: .token)
        try values.encodeIfPresent(baseURLOverride, forKey: .baseURLOverride)
        try values.encodeIfPresent(userEmail, forKey: .userEmail)
        try values.encodeIfPresent(iconSymbol, forKey: .iconSymbol)
        try values.encodeIfPresent(tintHex, forKey: .tintHex)
    }

    /// A changed token or base URL points at potentially different data, so the store
    /// fires `onRekeyed` to invalidate caches keyed by this account.
    func pointsAtDifferentBackend(than other: Self) -> Bool {
        token != other.token || serverIdentity != other.serverIdentity
    }
}
