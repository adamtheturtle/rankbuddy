//
//  HTMLText.swift
//  rankbuddy-macos
//

import AppKit
import SwiftUI

/// Renders an HTML fragment as formatted, selectable text.
///
/// HackerRank returns some text fields — a test's `instructions`, a question's
/// `problem_statement` — as HTML (#35). Shown verbatim they leak raw `<p>`/`<b>`/`<ul>`
/// markup, so this converts the HTML to an `AttributedString`, normalising the importer's
/// hard-coded fonts and colours so the text adopts the app's body font and adapts to
/// light/dark mode, while preserving bold/italic/monospace emphasis from the source.
struct HTMLText: View {
    let html: String
    var showsPlaceholder = true
    @State private var renderedHTML: String?
    @State private var attributed: AttributedString?

    private var displayedAttributed: AttributedString? {
        if renderedHTML == html, let attributed {
            return attributed
        }
        return HTMLRenderCache.attributed(for: html)
    }

    var body: some View {
        Group {
            if let displayedAttributed {
                Text(displayedAttributed)
            } else if showsPlaceholder, !html.isEmpty {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            } else {
                // A real (zero-size) view, not EmptyView: `.task` never fires on a view that
                // renders nothing, which would leave the render permanently pending.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .textSelection(.enabled)
        .task(id: html) { await renderHTML() }
    }

    @MainActor
    private func renderHTML() async {
        if let cached = HTMLRenderCache.attributed(for: html) {
            renderedHTML = html
            attributed = cached
            return
        }

        renderedHTML = nil
        attributed = nil
        await Task.yield()
        guard !Task.isCancelled else { return }

        let rendered = AttributedString.fromHTML(html)
        guard !Task.isCancelled else { return }

        HTMLRenderCache.store(rendered, for: html)
        renderedHTML = html
        attributed = rendered
    }
}

/// Renders HTML fragments with first-class layout for ordered lists.
struct HTMLFragmentText: View {
    let html: String
    var showsPlaceholder = true
    @State private var segmentedHTML: String?
    @State private var segments: [HTMLFragmentSegment]?

    private var displayedSegments: [HTMLFragmentSegment]? {
        if segmentedHTML == html, let segments {
            return segments
        }
        return HTMLFragmentSegmentCache.segments(for: html)
    }

    var body: some View {
        Group {
            if let displayedSegments {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(displayedSegments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case let .prose(prose):
                            if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HTMLText(html: prose, showsPlaceholder: showsPlaceholder)
                            }

                        case let .orderedList(items):
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("\(index + 1).")
                                            .font(.body.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 24, alignment: .trailing)

                                        HTMLText(html: item, showsPlaceholder: showsPlaceholder)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else if showsPlaceholder, !html.isEmpty {
                Text("Loading…")
                    .foregroundStyle(.secondary)
            } else {
                // A real (zero-size) view, not EmptyView, so `.task` below always fires.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: html) { await prepareSegments() }
    }

    @MainActor
    private func prepareSegments() async {
        if let cached = HTMLFragmentSegmentCache.segments(for: html) {
            segmentedHTML = html
            segments = cached
            return
        }

        segmentedHTML = nil
        segments = nil
        await Task.yield()
        guard !Task.isCancelled else { return }

        let prepared = HTMLFragmentSegment.segments(from: html)
        guard !Task.isCancelled else { return }

        HTMLFragmentSegmentCache.store(prepared, for: html)
        segmentedHTML = html
        segments = prepared
    }
}

private enum HTMLFragmentSegment {
    case prose(String)
    case orderedList([String])

    static func segments(from html: String) -> [Self] {
        let listPattern = #"(?is)<ol\b[^>]*>(.*?)</ol>"#
        guard let listExpression = try? NSRegularExpression(pattern: listPattern) else {
            return [.prose(html)]
        }

        // NSRegularExpression works in terms of NSString ranges, so the bridge is required here.
        // swiftlint:disable:next legacy_objc_type
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        var segments: [Self] = []
        var cursor = 0

        for match in listExpression.matches(in: html, range: fullRange) {
            if match.range.location > cursor {
                let range = NSRange(location: cursor, length: match.range.location - cursor)
                segments.append(.prose(nsHTML.substring(with: range)))
            }

            let listHTML = nsHTML.substring(with: match.range(at: 1))
            let items = orderedListItems(from: listHTML)
            if items.isEmpty {
                segments.append(.prose(nsHTML.substring(with: match.range)))
            } else {
                segments.append(.orderedList(items))
            }

            cursor = match.range.location + match.range.length
        }

        if cursor < nsHTML.length {
            segments.append(.prose(nsHTML.substring(from: cursor)))
        }

        return segments.isEmpty ? [.prose(html)] : segments
    }

    private static func orderedListItems(from html: String) -> [String] {
        let itemPattern = #"(?is)<li\b[^>]*>(.*?)</li>"#
        guard let itemExpression = try? NSRegularExpression(pattern: itemPattern) else { return [] }

        // swiftlint:disable:next legacy_objc_type
        let nsHTML = html as NSString
        let fullRange = NSRange(location: 0, length: nsHTML.length)
        return itemExpression.matches(in: html, range: fullRange).map { match in
            nsHTML.substring(with: match.range(at: 1))
        }
    }
}

@MainActor
private enum HTMLFragmentSegmentCache {
    private static let capacity = 80
    private static var values: [String: [HTMLFragmentSegment]] = [:]
    private static var keys: [String] = []

    static func segments(for html: String) -> [HTMLFragmentSegment]? {
        values[html]
    }

    static func store(_ segments: [HTMLFragmentSegment], for html: String) {
        guard values[html] == nil else { return }

        values[html] = segments
        keys.append(html)
        if keys.count > capacity {
            values[keys.removeFirst()] = nil
        }
    }
}

@MainActor
private enum HTMLRenderCache {
    private static let capacity = 80
    private static var values: [String: AttributedString] = [:]
    private static var keys: [String] = []

    static func attributed(for html: String) -> AttributedString? {
        values[html]
    }

    static func store(_ attributed: AttributedString, for html: String) {
        guard values[html] == nil else { return }

        values[html] = attributed
        keys.append(html)
        if keys.count > capacity {
            values[keys.removeFirst()] = nil
        }
    }
}

extension AttributedString {
    /// Builds an `AttributedString` from an HTML fragment, normalised for in-app display.
    ///
    /// Falls back to a plain-text attributed string of `html` if it cannot be parsed as
    /// HTML, so the user always sees the content (just without formatting).
    ///
    /// `@MainActor` because AppKit's HTML importer is only safe to use on the main thread.
    @MainActor static func fromHTML(_ html: String) -> AttributedString {
        guard let data = html.data(using: .utf8),
              let parsed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue
                  ],
                  documentAttributes: nil
              )
        else {
            return AttributedString(html)
        }

        var result = AttributedString(normalised(parsed))
        // The HTML importer appends a trailing newline after block elements; drop it so the
        // text doesn't render with a dangling blank line inside its Form section.
        while result.characters.last == "\n" {
            let last = result.index(result.endIndex, offsetByCharacters: -1)
            result.removeSubrange(last ..< result.endIndex)
        }
        return result
    }

    /// Replaces the importer's hard-coded fonts with the system body font (preserving
    /// bold/italic/monospace traits) and removes explicit colours, so the text inherits the
    /// app's appearance and adapts to light/dark mode.
    private static func normalised(_ attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: result.length)
        let body = NSFont.preferredFont(forTextStyle: .body)

        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let kept = traits.intersection([.bold, .italic, .monoSpace])
            let descriptor = body.fontDescriptor.withSymbolicTraits(kept)
            let font = NSFont(descriptor: descriptor, size: body.pointSize) ?? body
            result.addAttribute(.font, value: font, range: range)
        }
        result.removeAttribute(.foregroundColor, range: full)
        return result
    }
}

#Preview {
    Form {
        Section("Instructions") {
            HTMLText(html: """
            <p>Solve <b>all</b> questions within the <i>time limit</i>. You may use:</p>
            <ul><li>The standard library</li><li>One scratch file</li></ul>
            <p>Inputs &amp; outputs are validated. See <code>main()</code> for the entry point.</p>
            """)
        }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 320)
}
