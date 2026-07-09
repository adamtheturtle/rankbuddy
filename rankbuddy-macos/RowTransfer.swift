//
//  RowTransfer.swift
//  rankbuddy-macos
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Public copy/drag representations for a selectable list row (#123/#124).
///
/// A row can carry concise text for plain-text targets, optional tabular fields for
/// spreadsheets, and an optional URL for browser or URL-aware drop targets. The generic
/// `LoadableList` owns the command and drag plumbing; each concrete screen owns the data shape.
nonisolated struct RowTransfer {
    let title: String
    var subtitle: String?
    var url: URL?
    var fields: [(String, String)]

    init(title: String, subtitle: String? = nil, url: URL? = nil, fields: [(String, String)] = []) {
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.fields = fields
    }

    /// A compact plain-text fallback for TextEdit, Notes, Slack, and similar targets.
    var plainText: String {
        var lines = [title]
        if let subtitle, !subtitle.isEmpty { lines.append(subtitle) }
        if let url { lines.append(url.absoluteString) }
        return lines.joined(separator: "\n")
    }

    /// A tab-delimited row for spreadsheet-like targets. Falls back to public text pieces when
    /// the caller did not provide explicit fields.
    var tabularRow: [String] {
        if !fields.isEmpty { return fields.map(\.1) }
        var values = [title]
        if let subtitle, !subtitle.isEmpty { values.append(subtitle) }
        if let url { values.append(url.absoluteString) }
        return values
    }

    var tabularText: String {
        Self.tabularText([self])
    }

    /// A multi-row plain-text representation that keeps each row readable when pasted into a
    /// normal text field.
    static func plainText(_ rows: [RowTransfer]) -> String {
        rows.map(\.plainText).joined(separator: "\n\n")
    }

    /// A multi-row TSV representation suitable for Numbers, Excel, and Google Sheets.
    static func tabularText(_ rows: [RowTransfer]) -> String {
        rows.map { row in
            row.tabularRow.map(Self.escapeTabularField).joined(separator: "\t")
        }
        .joined(separator: "\n")
    }

    /// Builds copy providers for Command-C. The first provider is the readable plain-text form;
    /// the second is TSV when the selected rows expose tabular fields.
    static func itemProviders(for rows: [RowTransfer]) -> [NSItemProvider] {
        guard !rows.isEmpty else { return [] }

        var providers = [NSItemProvider(object: plainText(rows) as NSString)]
        if rows.contains(where: { !$0.fields.isEmpty }) {
            let tsv = tabularText(rows)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.tabSeparatedText.identifier, visibility: .all) {
                completion in
                completion(Data(tsv.utf8), nil)
                return nil
            }
            providers.append(provider)
        }
        if rows.count == 1, let url = rows.first?.url {
            providers.append(NSItemProvider(object: url as NSURL))
        }
        return providers
    }

    /// A single drag pasteboard item carrying every row's public data, used when a multi-row
    /// selection is dragged (#124): plain text and TSV keep all rows, and the URL type carries the
    /// first row's link so URL-only drop targets (a browser tab) still receive something useful.
    /// Returns `nil` for an empty selection so the caller can fall back to the single-row path.
    static func pasteboardItem(for rows: [RowTransfer]) -> NSPasteboardItem? {
        guard !rows.isEmpty else { return nil }

        let item = NSPasteboardItem()
        item.setString(plainText(rows), forType: .string)
        item.setString(tabularText(rows), forType: NSPasteboard.PasteboardType(UTType.tabSeparatedText.identifier))
        if let url = rows.lazy.compactMap(\.url).first {
            item.setString(url.absoluteString, forType: .URL)
        }
        return item
    }

    /// Builds an AppKit pasteboard item for row dragging. The optional favourite ref is the
    /// app-private in-process payload; public string and URL types let other apps receive useful
    /// data from the same drag.
    func pasteboardItem(favoriteRef: FavoriteRef? = nil) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(plainText, forType: .string)
        item.setString(tabularText, forType: NSPasteboard.PasteboardType(UTType.tabSeparatedText.identifier))
        if let url {
            item.setString(url.absoluteString, forType: .URL)
        }
        if let favoriteRef, let data = try? JSONEncoder().encode(favoriteRef) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.rankBuddyFavorite.identifier))
        }
        return item
    }

    private static func escapeTabularField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
