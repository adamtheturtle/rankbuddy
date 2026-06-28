//
//  InlineEditableTitle.swift
//  rankbuddy-macos
//

import SwiftUI

/// The pure commit decision for an inline edit (#95), factored out so it is unit-tested.
nonisolated enum InlineEdit {
    /// The value to write when committing an edit, or `nil` when nothing should be written —
    /// the text is unchanged (ignoring surrounding whitespace) or empty. Returns the trimmed
    /// value so a rename never writes leading/trailing spaces.
    static func commitValue(original: String, edited: String) -> String? {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != original.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        return trimmed
    }
}

/// An inline-editable detail title (#95): reads as a plain title until hovered, when a subtle
/// pencil fades in; clicking it (or the pencil) turns it into a field that commits on Return or
/// focus-loss, writing optimistically through `onCommit`. Mirrors PadBuddy's `InlineEditableTitle`.
///
/// Editing is offered only when `isEditable` is true (e.g. a writable entity on a live or demo
/// account, not while offline); otherwise it renders exactly like the previous static title.
struct InlineEditableTitle: View {
    let title: String
    var isEditable: Bool
    /// Writes the new value, returning whether it succeeded; a failure reverts to the title.
    var onCommit: (String) async -> Bool

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovering = false
    @State private var isSaving = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editorField
            } else if isEditable {
                editableTitle
            } else {
                plainTitle
            }
        }
        .font(.title2.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The static title shown in read-only contexts — identical to the previous header title.
    private var plainTitle: some View {
        Text(title)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The at-rest title that reveals a pencil on hover and begins editing on click.
    private var editableTitle: some View {
        HStack(spacing: 6) {
            Text(title)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if isHovering {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        // The whole title is the affordance, so a click anywhere on it begins editing.
        .onTapGesture { beginEditing() }
        .help("Click to rename")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to rename")
    }

    private var editorField: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .disabled(isSaving)
                .onSubmit { Task { await commit() } }
                // Commit when focus leaves the field (clicking elsewhere), mirroring PadBuddy.
                .onChange(of: fieldFocused) { _, focused in
                    if !focused, isEditing { Task { await commit() } }
                }

            if isSaving {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func beginEditing() {
        draft = title
        isEditing = true
        fieldFocused = true
    }

    private func commit() async {
        guard isEditing, !isSaving else { return }
        guard let value = InlineEdit.commitValue(original: title, edited: draft) else {
            // No change (or empty): just leave edit mode without writing.
            isEditing = false
            return
        }

        isSaving = true
        let succeeded = await onCommit(value)
        isSaving = false
        isEditing = false
        // On failure the parent keeps the old title, so reverting is simply leaving edit mode.
        _ = succeeded
    }
}

#Preview("Editable") {
    Form {
        InlineEditableTitle(title: "Backend Screen", isEditable: true) { _ in true }
        Section("Properties") {
            LabeledContent("Duration", value: "60 min")
        }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 200)
}

#Preview("Read-only") {
    Form {
        InlineEditableTitle(title: "Backend Screen", isEditable: false) { _ in true }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 120)
}
