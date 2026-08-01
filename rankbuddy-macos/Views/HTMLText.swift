//
//  HTMLText.swift
//  rankbuddy-macos
//

import AppKit
import SwiftUI

// The renderer, balanced fragment parser, and their shared cache stay together so the parser's
// source ranges and rendering cases cannot drift across files.
// swiftlint:disable file_length

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

        let rendered = await Task.detached(priority: .userInitiated) {
            AttributedString.fromHTML(html)
        }.value
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

                        case let .orderedList(items, start, step, markerStyle):
                            let markers = HTMLFragmentSegment.markerValues(
                                for: items, start: start, step: step
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("\(markerStyle.marker(for: markers[index])).")
                                            .font(.body.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .frame(minWidth: 24, alignment: .trailing)

                                        HTMLText(html: item.html, showsPlaceholder: showsPlaceholder)
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

        let prepared = await Task.detached(priority: .userInitiated) {
            HTMLFragmentSegment.segments(from: html)
        }.value
        guard !Task.isCancelled else { return }

        HTMLFragmentSegmentCache.store(prepared, for: html)
        segmentedHTML = html
        segments = prepared
    }
}

nonisolated enum HTMLFragmentSegment: Equatable {
    struct OrderedItem: Equatable {
        let html: String
        let explicitValue: Int?
    }

    case prose(String)
    case orderedList(items: [OrderedItem], start: Int, step: Int, markerStyle: OrderedListMarkerStyle)

    static func segments(from html: String) -> [Self] {
        let searchableHTML = maskingIgnoredMarkup(in: html)
        // NSRegularExpression works in terms of NSString ranges, so the bridge is required here.
        // swiftlint:disable:next legacy_objc_type
        let nsHTML = html as NSString
        var segments: [Self] = []
        var cursor = 0

        for element in balancedElements(named: "ol", in: searchableHTML) {
            if element.full.location > cursor {
                let range = NSRange(location: cursor, length: element.full.location - cursor)
                segments.append(.prose(nsHTML.substring(with: range)))
            }

            let attributes = nsHTML.substring(with: element.attributes)
            let listHTML = nsHTML.substring(with: element.content)
            let items = orderedListItems(from: listHTML)
            if items.isEmpty {
                segments.append(.prose(nsHTML.substring(with: element.full)))
            } else {
                let reversed = hasAttribute("reversed", in: attributes)
                let explicitStart = integerAttribute("start", in: attributes)
                let start = explicitStart ?? (reversed ? items.count : 1)
                let markerStyle = OrderedListMarkerStyle(htmlType: attribute("type", in: attributes))
                segments.append(.orderedList(
                    items: items,
                    start: start,
                    step: reversed ? -1 : 1,
                    markerStyle: markerStyle
                ))
            }

            cursor = element.full.location + element.full.length
        }

        if cursor < nsHTML.length {
            segments.append(.prose(nsHTML.substring(from: cursor)))
        }

        return segments.isEmpty ? [.prose(html)] : segments
    }

    static func markerValues(for items: [OrderedItem], start: Int, step: Int) -> [Int] {
        var next = start
        return items.map { item in
            let marker = item.explicitValue ?? next
            next = marker + step
            return marker
        }
    }

    private static func orderedListItems(from html: String) -> [OrderedItem] {
        // swiftlint:disable:next legacy_objc_type
        let nsHTML = html as NSString
        let searchableHTML = maskingIgnoredMarkup(in: html)
        return balancedElements(named: "li", in: searchableHTML).map { element in
            OrderedItem(
                html: nsHTML.substring(with: element.content),
                explicitValue: integerAttribute("value", in: nsHTML.substring(with: element.attributes))
            )
        }
    }

    private struct ElementRanges {
        let full: NSRange
        let attributes: NSRange
        let content: NSRange
    }

    /// Returns balanced top-level elements of `name`, retaining nested elements inside their
    /// parent's content range. Ignored markup has already been replaced with equal-length spaces,
    /// so every range maps directly back to the original HTML.
    private static func balancedElements(named name: String, in html: String) -> [ElementRanges] {
        // swiftlint:disable:next legacy_objc_type
        let source = html as NSString
        var result: [ElementRanges] = []
        var depth = 0
        var opening: NSRange?
        for range in elementTagRanges(named: name, in: html) {
            let token = source.substring(with: range)
            if token.hasPrefix("</") {
                guard depth > 0 else { continue }

                depth -= 1
                if depth == 0, let opening {
                    let contentStart = opening.location + opening.length
                    result.append(ElementRanges(
                        full: NSRange(
                            location: opening.location,
                            length: range.location + range.length - opening.location
                        ),
                        attributes: attributeRange(tag: name, opening: opening),
                        content: NSRange(location: contentStart, length: range.location - contentStart)
                    ))
                }
            } else if !token.hasSuffix("/>") {
                if depth == 0 {
                    opening = range
                }
                depth += 1
            }
        }
        return result
    }

    /// Scans complete tags while respecting quoted attributes, so markup-looking text inside an
    /// attribute value is never treated as a structural element.
    private static func elementTagRanges(named name: String, in html: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var index = html.startIndex
        while let opening = html[index...].firstIndex(of: "<") {
            guard let closing = tagClosingBracket(in: html, after: opening) else { break }

            let end = html.index(after: closing)
            let body = html[html.index(after: opening) ..< closing]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = body.hasPrefix("/") ? body.dropFirst() : body[...]
            if candidate.prefix(while: \.isLetter).lowercased() == name.lowercased() {
                ranges.append(NSRange(opening ..< end, in: html))
            }
            index = end
        }
        return ranges
    }

    private static func tagClosingBracket(in html: String, after opening: String.Index) -> String.Index? {
        var currentQuote: Character?
        var index = html.index(after: opening)
        while index < html.endIndex {
            let character = html[index]
            if let activeQuote = currentQuote {
                if character == activeQuote {
                    currentQuote = nil
                }
            } else if character == "\"" || character == "'" {
                currentQuote = character
            } else if character == ">" {
                return index
            }
            html.formIndex(after: &index)
        }
        return nil
    }

    private static func attributeRange(tag name: String, opening: NSRange) -> NSRange {
        let start = opening.location + 1 + name.utf16.count
        return NSRange(location: start, length: max(0, opening.location + opening.length - start - 1))
    }

    private static func hasAttribute(_ name: String, in attributes: String) -> Bool {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?i)(?:^|\s)"# + escapedName + #"(?:\s|=|$)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }

        let range = NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)
        return expression.firstMatch(in: attributes, range: range) != nil
    }

    private static func integerAttribute(_ name: String, in attributes: String) -> Int? {
        attribute(name, in: attributes).flatMap(Int.init)
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?i)(?:^|\s)"# + escapedName
            + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(attributes.startIndex ..< attributes.endIndex, in: attributes)
        guard let match = expression.firstMatch(in: attributes, range: range) else { return nil }

        // swiftlint:disable:next legacy_objc_type
        let source = attributes as NSString
        for index in 1 ..< match.numberOfRanges where match.range(at: index).location != NSNotFound {
            return source.substring(with: match.range(at: index)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Replaces ignored HTML regions with equal-length whitespace so regex match offsets still
    /// map exactly onto the original source.
    private static func maskingIgnoredMarkup(in html: String) -> String {
        let patterns = [
            #"(?s)<!--.*?-->"#,
            #"(?is)<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>"#,
            #"(?is)<(?:script|style)\b[^>]*>.*\z"#
        ]
        let masked = NSMutableString(string: html)
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }

            let fullRange = NSRange(location: 0, length: masked.length)
            for match in expression.matches(in: masked as String, range: fullRange).reversed() {
                masked.replaceCharacters(
                    in: match.range,
                    with: String(repeating: " ", count: match.range.length)
                )
            }
        }
        return masked as String
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
    nonisolated static func fromHTML(_ html: String) -> AttributedString {
        let safeHTML = resourceSafeHTML(html)
        guard let data = safeHTML.data(using: .utf8),
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

    /// Removes constructs that can cause AppKit's HTML importer to load a remote resource.
    nonisolated static func resourceSafeHTML(_ html: String) -> String {
        let patterns = [
            #"(?is)<(script|style|iframe|object|video|audio)\b[^>]*>.*?</\1\s*>"#,
            #"(?is)<(?:link|meta|base|img|embed|source|track)\b[^>]*>"#,
            #"(?is)\s+style\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#,
            #"(?is)\s+(?:src|srcset|href|xlink:href|background|poster)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#
        ]
        return patterns.reduce(html) { value, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }

            let range = NSRange(value.startIndex ..< value.endIndex, in: value)
            return expression.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        }
    }

    /// Replaces the importer's hard-coded fonts with the system body font (preserving
    /// bold/italic/monospace traits) and removes explicit colours, so the text inherits the
    /// app's appearance and adapts to light/dark mode.
    nonisolated static func normalised(_ attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: result.length)
        let body = NSFont.preferredFont(forTextStyle: .body)

        var fontRuns: [(range: NSRange, traits: NSFontDescriptor.SymbolicTraits)] = []
        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            fontRuns.append((range, traits.intersection([.bold, .italic, .monoSpace])))
        }
        result.addAttribute(.font, value: body, range: full)
        for run in fontRuns {
            let descriptor = body.fontDescriptor.withSymbolicTraits(run.traits)
            let font = NSFont(descriptor: descriptor, size: body.pointSize) ?? body
            result.addAttribute(.font, value: font, range: run.range)
        }
        result.removeAttribute(.foregroundColor, range: full)
        result.removeAttribute(.backgroundColor, range: full)
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

// swiftlint:enable file_length
