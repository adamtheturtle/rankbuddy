//
//  SharedViews.swift
//  rankbuddy-macos
//

import BuddyAppKit
import FastList
import Flow
import SwiftUI

/// Renders tags as wrapping pill chips. Renders nothing when there are no tags, so a
/// detail form can drop the whole section for tagless items.
struct TagList: View {
    let tags: [String]?

    var body: some View {
        let tags = uniqueTags(tags)
        if !tags.isEmpty {
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

/// The detail pane's Share + Open-in-browser actions, mirroring PadBuddy's pad-detail toolbar.
/// Uses PadBuddy's exact icons (`square.and.arrow.up`, `doc.text.image`) and short "Open" title so
/// the two apps' detail toolbars match, and routes Open through the browser preference (#63). Both
/// stay on the default toolbar. A `nil` URL (e.g. the merged view, where the owning account is
/// ambiguous) omits both items, exactly like PadBuddy's `if let url = pad.webURL`.
struct DetailLinkToolbarContent: CustomizableToolbarContent {
    let url: URL?
    /// The noun used in the help / accessibility text (e.g. "test", "interview", "question").
    var noun: String

    var body: some CustomizableToolbarContent {
        if let url {
            ToolbarItem(id: "share", placement: .primaryAction) {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share \(noun)")
                .accessibilityLabel("Share \(noun)")
            }
            ToolbarItem(id: "open", placement: .primaryAction) {
                Button {
                    BrowserSettings.open(url)
                } label: {
                    // Short title ("Open", not "Open Test") so it doesn't truncate when the
                    // detail column is narrow; the accessibility label stays descriptive.
                    Label("Open", systemImage: "doc.text.image")
                }
                .help("Open the \(noun) in your browser")
                .accessibilityLabel("Open \(noun)")
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

    if let link, let url = URL.remoteWebURL(from: link) {
        items.append(.button(title: openLabel) { BrowserSettings.open(url) })
        items.append(.button(title: "Copy Link") { Clipboard.copy(url.absoluteString) })
    }

    items.append(.button(title: copyLabel) { Clipboard.copy(copyText) })
    return items
}

/// Fixed metrics for `FastList` rows, matching PadBuddy so RankBuddy's lists share the same
/// comfortable row height instead of sizing tightly to a row's content (which read as squished).
enum FastListRowMetrics {
    /// Fixed hosted-row height for the AppKit `FastList` backend. Giving `NSTableView` one
    /// stable intrinsic height (rather than per-row automatic height discovery as it recycles
    /// SwiftUI hosting cells during fast scrolls) both smooths scrolling and gives every row the
    /// same breathing room PadBuddy's rows have.
    static let macHeight: CGFloat = 64
}

extension View {
    /// Frames a `FastList` row's hosted content to the shared fixed height on macOS, so rows
    /// centre their content at a consistent, comfortable height (matching PadBuddy). A no-op on
    /// other platforms, where the row sizes to its content.
    @ViewBuilder
    func fixedFastListRowHeight() -> some View {
        #if os(macOS)
            frame(height: FastListRowMetrics.macHeight)
        #else
            self
        #endif
    }

    func listRowTextColumn() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
    }

    func listRowTitleStyle(fullText: String) -> some View {
        font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail).help(fullText).accessibilityLabel(fullText)
    }

    func listRowMetadataStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
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

/// A clickable favourite star for a list row, matching PadBuddy: always shown (faint when the
/// item isn't favourited), toggling the favourite on click with a symbol-swap animation.
///
/// It is interactive, so it must sit *outside* a row's hit-transparent content (see the
/// accessory column in `LoadableList`): a click on the star toggles the favourite, while a click
/// anywhere else on the row still falls through to the table for selection.
struct FavoriteStarButton: View {
    let isFavorite: Bool
    /// The row's title, used only to phrase the accessibility label.
    let title: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        // Keep non-favourite stars faint but present, so the toggle is discoverable on every
        // row without the star competing with the row's own content (matches PadBuddy).
        .opacity(isFavorite ? 1 : 0.35)
        .help(isFavorite ? "Remove from Favourites" : "Add to Favourites")
        .accessibilityLabel(isFavorite ? "Remove \(title) from Favourites"
            : "Add \(title) to Favourites")
    }
}

/// A right-aligned relative date ("2 months ago") in an adaptive trailing column for a list
/// row. Reserves a minimum width even when the date is missing, so
/// stars and titles stay vertically aligned across rows whether or not a row has a date.
struct RowDateLabel: View {
    let date: Date?

    static let minimumColumnWidth: CGFloat = 60, maximumColumnWidth: CGFloat = 160

    var body: some View {
        Group {
            if let date {
                let labels = RelativeDateLabel.labels(for: date)
                Text(labels.relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(labels.tooltip)
                    .accessibilityLabel(labels.tooltip)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: Self.minimumColumnWidth, maxWidth: Self.maximumColumnWidth, alignment: .trailing)
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
                    "Add an account to get started, or explore the demo first.")
            } actions: {
                SettingsLink {
                    Text("Add Account…")
                }
                .buttonStyle(.borderedProminent)

                Button("Add Demo Account") { store.add(.demo) }

                GetTokenLink()
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

/// Compact native list/detail state used for loading, empty, no-results, no-selection, and
/// failure surfaces without oversized marketing-style placeholders.
struct CompactStateView: View {
    let title: String
    let systemImage: String
    let message: String
    var isLoading = false
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isLoading {
                ProgressView().controlSize(.small)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    if let actionSystemImage {
                        Label(actionTitle, systemImage: actionSystemImage)
                    } else {
                        Text(actionTitle)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A link to where a HackerRank for Work personal access token is generated, so a new user
/// can find their token before connecting an account.
struct GetTokenLink: View {
    private static let url = URL(string: "https://www.hackerrank.com/work/settings/token") ?? Account.defaultBaseURL

    var body: some View {
        Link("Get a Token", destination: Self.url)
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
            LabeledContent(label) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A detail-form row that opens a related list in its own window. Replaces the earlier
/// `NavigationLink` pushes: pushing a full `LoadableList` (with its own split panes, search
/// field, and customizable toolbar) inside a detail pane nests navigation stacks in a way that
/// wedges the window — the sidebar stops responding and the toolbar disappears.
struct WindowLinkRow: View {
    let title: String
    let systemImage: String
    let value: DetailWindowValue

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(value: value)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(title.lowercased()) in a new window")
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
