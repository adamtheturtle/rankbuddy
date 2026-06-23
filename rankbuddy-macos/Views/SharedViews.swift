import SwiftUI

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
