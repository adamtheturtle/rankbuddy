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
    favorite: (isFavorite: Bool, toggle: () -> Void)? = nil
) -> [MenuItem] {
    var items: [MenuItem] = []

    if let favorite {
        items.append(.button(
            title: favorite.isFavorite ? "Remove from Favourites" : "Add to Favourites",
            action: favorite.toggle
        ))
        items.append(.separator)
    }

    if let link, let url = URL(string: link) {
        items.append(.button(title: openLabel) { URLOpener.open(url) })
        items.append(.button(title: "Copy Link") { Clipboard.copy(url.absoluteString) })
    }

    items.append(.button(title: copyLabel) { Clipboard.copy(copyText) })
    return items
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

/// Shown when a section needs an account but none is configured.
struct NoAccountView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No account", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("Add a HackerRank account in Settings to get started.")
        } actions: {
            SettingsLink {
                Text("Open Settings")
            }
        }
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
