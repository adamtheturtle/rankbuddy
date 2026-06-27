import BuddyAppKit
import FastList
import Flow
import SwiftUI

/// Renders tags as wrapping pill chips. Renders nothing when there are no tags, so a
/// detail form can drop the whole section for tagless items.
struct TagList: View {
    let tags: [String]?

    var body: some View {
        if let tags, !tags.isEmpty {
            HFlow(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("Tag: \(tag)")
                }
            }
        }
    }
}

/// Builds a row's native context menu (`FastList`'s `MenuItem`s, since the hosted SwiftUI
/// row content is hit-transparent and a SwiftUI `.contextMenu` on it would never fire).
///
/// - Parameters:
///   - copyLabel: The menu title for copying `copyText` (e.g. "Copy Name").
///   - copyText: The text placed on the pasteboard by the copy action.
///   - link: An optional web URL string; when it parses, an open/copy-link pair is added.
///   - openLabel: The menu title for the open-in-browser action.
///   - favorite: when non-nil, a leading favourite toggle reflecting `isFavorite` (#25).
@MainActor
func rowMenuItems(
    copyLabel: String,
    copyText: String,
    link: String? = nil,
    openLabel: String = "Open in Browser",
    favorite: (isFavorite: Bool, toggle: () -> Void)? = nil,
    openInWindow: (() -> Void)? = nil
) -> [MenuItem] {
    var items: [MenuItem] = []

    if let openInWindow {
        items.append(.button(title: "Open in New Window", action: openInWindow))
        items.append(.separator)
    }

    if let favorite {
        items.append(.button(
            title: favorite.isFavorite ? "Remove from Favourites" : "Add to Favourites",
            action: favorite.toggle
        ))
        items.append(.separator)
    }

    if let link, let url = URL(string: link) {
        items.append(.button(title: openLabel) { BrowserSettings.open(url) })
        items.append(.button(title: "Copy Link") { Clipboard.copy(url.absoluteString) })
    }

    items.append(.button(title: copyLabel) { Clipboard.copy(copyText) })
    return items
}

/// A relative timestamp ("2 months ago") parsed from an ISO string, with the absolute date
/// as a tooltip. Renders nothing when the string is missing or unparseable. Matches
/// PadBuddy's list rows via buddy-kit's memoised `RelativeDateLabel`.
struct RelativeDateText: View {
    let iso: String?
    var prefix: String = ""

    var body: some View {
        if let date = DisplayFormat.parseDate(iso) {
            let labels = RelativeDateLabel.labels(for: date)
            Text(prefix.isEmpty ? labels.relative : "\(prefix) \(labels.relative)")
                .help(labels.tooltip)
        }
    }
}

/// A small star shown on a favourited row. Renders nothing when `isFavorite` is false, so
/// rows stay clean at rest (#25).
struct FavoriteIndicator: View {
    let isFavorite: Bool

    var body: some View {
        if isFavorite {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
                .accessibilityLabel("Favourite")
        }
    }
}

/// Shown when a section needs an account but none is configured. On first run (no accounts
/// at all) it's a small onboarding surface explaining what RankBuddy needs, with a one-click
/// demo so the app can be explored before connecting a real token.
struct NoAccountView: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("Welcome to RankBuddy", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("RankBuddy connects to HackerRank for Work with a personal access token, " +
                    "then keeps your tests, candidates, questions, and interviews a click away. " +
                    "Add an account to get started — or explore the demo first.")
            } actions: {
                SettingsLink {
                    Text("Add Account…")
                }
                .buttonStyle(.borderedProminent)

                Button("Add Demo Account") { store.add(.demo) }

                GetAPIKeyLink()
            }
        } else {
            ContentUnavailableView {
                Label("No account selected", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Choose one of your saved accounts in Settings.")
            } actions: {
                SettingsLink {
                    Text("Open Settings")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A link to where a HackerRank for Work personal access token is generated, so a new user
/// can find their key before connecting an account.
struct GetAPIKeyLink: View {
    private static let url = URL(string: "https://www.hackerrank.com/work") ?? Account.defaultBaseURL

    var body: some View {
        Link("Get an API key", destination: Self.url)
            .font(.callout)
    }
}

/// A banner shown over the lists when the current account's token has been rejected
/// mid-session (#40), pointing the user at Settings to fix it.
struct UnauthorizedBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("This account's token was rejected. Update it in Settings.")
                .font(.callout)
            Spacer()
            SettingsLink { Text("Open Settings") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}

/// A `LabeledContent` row that renders only when the value is present and non-empty, so
/// detail forms can list every field without showing blank rows for missing data.
struct OptionalRow: View {
    let label: String
    let value: String?

    init(_ label: String, _ value: String?) {
        self.label = label
        self.value = value
    }

    var body: some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
                .textSelection(.enabled)
        }
    }
}

#Preview("Welcome (first run)") {
    NoAccountView()
        .environment(AccountStore.rankBuddy(isTesting: true))
        .frame(width: 520, height: 380)
}

#Preview("Unauthorized banner") {
    UnauthorizedBanner()
        .frame(width: 520)
}
