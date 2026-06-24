import AppKit
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

/// Copies `text` to the general pasteboard.
@MainActor
func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

extension View {
    /// Adds a list-row context menu with a copy action and, when a web link is present,
    /// open-in-browser and copy-link actions.
    ///
    /// - Parameters:
    ///   - copyLabel: The menu title for copying `copyText` (e.g. "Copy Name").
    ///   - copyText: The text placed on the pasteboard by the copy action.
    ///   - link: An optional web URL string; when it parses, an open/copy-link pair is shown.
    ///   - openLabel: The menu title for the open-in-browser action.
    func rowContextMenu(
        copyLabel: String,
        copyText: String,
        link: String? = nil,
        openLabel: String = "Open in Browser"
    ) -> some View {
        let url = link.flatMap(URL.init(string:))
        return contextMenu {
            if let url {
                Link(destination: url) {
                    Label(openLabel, systemImage: "safari")
                }
                Button {
                    copyToPasteboard(url.absoluteString)
                } label: {
                    Label("Copy Link", systemImage: "link")
                }
            }
            Button {
                copyToPasteboard(copyText)
            } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
            }
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
