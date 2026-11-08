//
//  NativeFormPresentation.swift
//  rankbuddy-macos
//

import SwiftUI

extension EnvironmentValues {
    @Entry var nativeFormOmissionLabel = "Default"
}

/// Keeps required labels inline and optional values beneath their inclusion switch.
struct NativeFormValue<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let title {
            LabeledContent(title) { content() }
        } else {
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NativeFormHelp: View {
    let html: String

    private var text: String {
        MarkdownExport.plainText(fromHTML: html)
    }

    var body: some View {
        Group {
            if text.count > 180 || text.split(separator: "\n").count > 3 {
                DisclosureGroup("Details") { helpText.padding(.top, 4) }
            } else if !text.isEmpty {
                helpText
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var helpText: some View {
        Text(text).frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}
