import Foundation

/// Opt-in for the app's write actions (#12).
///
/// RankBuddy is read-only by default — it only ever issued GETs. Write flows (the first
/// being "invite a candidate to a test") mutate real data on HackerRank, so they are
/// hidden until the user explicitly enables them in Settings. Centralised here so the
/// `UserDefaults` key is shared by the Settings toggle and the views that gate on it.
enum WriteActions {
    /// The `UserDefaults`/`@AppStorage` key backing the opt-in. Defaults to `false`
    /// (read-only) when unset.
    static let defaultsKey = "rb.writeActionsEnabled"
}
