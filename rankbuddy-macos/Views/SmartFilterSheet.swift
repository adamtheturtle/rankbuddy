//
//  SmartFilterSheet.swift
//  rankbuddy-macos
//

import SwiftUI

/// A small sheet that takes a natural-language query and asks the on-device interpreter to turn
/// it into the list's filters (#91). The host (`LoadableList`) owns the interpretation and the
/// filter bindings; this view is just the entry surface — a field, an interpreting state, and a
/// plain explanation when the model couldn't map the request to anything. See `SearchInterpreter`.
struct SmartFilterSheet: View {
    @Binding var text: String
    /// True while the on-device model is interpreting, so the sheet shows progress.
    let isInterpreting: Bool
    /// True after an attempt the model couldn't map to any filter, so the sheet explains why
    /// nothing changed instead of silently closing.
    let failed: Bool
    let placeholder: LocalizedStringKey
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Smart Filter", systemImage: "sparkle.magnifyingglass")
                .font(.headline)

            Text("Describe what you're looking for in plain language — it's interpreted on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2 ... 4)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(submitIfPossible)
                .disabled(isInterpreting)

            if isInterpreting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Interpreting…").foregroundStyle(.secondary)
                }
                .font(.callout)
            } else if failed {
                Label(
                    "Couldn't match that to any filter. Try naming a status, language, or a time like \"last 7 days\".",
                    systemImage: "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: submitIfPossible)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty || isInterpreting)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { fieldFocused = true }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitIfPossible() {
        guard !trimmed.isEmpty, !isInterpreting else { return }

        onSubmit()
    }
}

#Preview("Empty") {
    SmartFilterSheet(
        text: .constant(""),
        isInterpreting: false,
        failed: false,
        placeholder: "e.g. python questions from last week",
        onSubmit: {},
        onCancel: {}
    )
}

#Preview("No match") {
    SmartFilterSheet(
        text: .constant("something unmatchable"),
        isInterpreting: false,
        failed: true,
        placeholder: "e.g. failed candidates this month",
        onSubmit: {},
        onCancel: {}
    )
}
