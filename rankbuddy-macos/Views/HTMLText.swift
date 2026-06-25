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

    var body: some View {
        Text(AttributedString.fromHTML(html))
            .textSelection(.enabled)
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
