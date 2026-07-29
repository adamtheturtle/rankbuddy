//
//  EditableRows.swift
//  rankbuddy-macos
//

import SwiftUI

// These small, related form controls share save/revert behavior and are maintained together.
// swiftlint:disable file_length

// Form rows that edit one field and save it immediately — PadBuddy's per-field commit
// pattern (its pad-detail Properties card), adopted here so detail views stay live
// documents instead of round-tripping through modal edit sheets (#147).
//
// Each row owns a draft of its value, commits on submit/focus-loss (text) or on change
// (picker/toggle), shows a small spinner while the write is in flight, and reverts the
// draft when the caller reports failure. The caller owns error presentation.

/// A label + text field row that commits on submit or focus loss.
struct EditableTextRow: View {
    let label: String
    let value: String
    var displayValue: String?
    var prompt: String = ""
    /// Persists the trimmed new value; returns whether it saved (false reverts the draft).
    let commit: (String) async -> Bool

    @State private var draft = ""
    @State private var isSaving = false
    @State private var isEditingDisplayValue = false
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                if let displayValue, !isEditingDisplayValue {
                    Text(displayValue)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button {
                        draft = value
                        isEditingDisplayValue = true
                        Task { @MainActor in isFocused = true }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.plain)
                    .help("Edit \(label.lowercased())")
                } else {
                    TextField(label, text: $draft, prompt: fieldPrompt)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .labelsHidden()
                        .focused($isFocused)
                        .onSubmit {
                            Task {
                                await save()
                                finishDisplayValueEditing()
                            }
                        }
                        .onChange(of: isFocused) { _, focused in
                            if !focused {
                                Task {
                                    await save()
                                    finishDisplayValueEditing()
                                }
                            }
                        }
                }
                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in draft = newValue }
    }

    private var fieldPrompt: Text? {
        guard isFocused, !prompt.isEmpty else { return nil }

        return Text(prompt)
    }

    @MainActor
    private func finishDisplayValueEditing() {
        guard displayValue != nil else { return }

        isFocused = false
        isEditingDisplayValue = false
    }

    private func save() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }
        if await !commit(trimmed) {
            draft = value
        }
    }
}

/// A label + structured multi-select row for HackerRank language codes.
struct EditableLanguagesRow: View {
    let value: [String]?
    let commit: ([String]?) async -> Bool

    @State private var draft: [String] = []
    @State private var isSaving = false

    var body: some View {
        LabeledContent("Languages") {
            HStack(spacing: 6) {
                Text(displayText)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(draft.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)

                Menu {
                    ForEach(menuOptions, id: \.code) { option in
                        Button {
                            Task { await toggle(option.code) }
                        } label: {
                            if draft.contains(option.code) {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }

                    if !draft.isEmpty {
                        Divider()
                        Button("Clear Languages") {
                            Task { await save([]) }
                        }
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .help("Edit languages")
                .disabled(isSaving)

                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .onAppear { draft = normalized(value) }
        .onChange(of: value ?? []) { _, newValue in draft = normalized(newValue) }
    }

    private var displayText: String {
        DisplayFormat.languages(draft) ?? "None"
    }

    private var menuOptions: [(code: String, name: String)] {
        let knownCodes = Set(DisplayFormat.hackerRankLanguageOptions.map(\.code))
        let customOptions = draft
            .filter { !knownCodes.contains($0) }
            .map { (code: $0, name: DisplayFormat.languageName($0)) }
        return DisplayFormat.hackerRankLanguageOptions + customOptions
    }

    private func toggle(_ code: String) async {
        var newValue = draft
        if let index = newValue.firstIndex(of: code) {
            newValue.remove(at: index)
        } else {
            newValue.append(code)
        }
        await save(newValue)
    }

    private func save(_ newValue: [String]) async {
        let normalizedValue = normalized(newValue)
        guard normalizedValue != normalized(value), !isSaving else { return }

        draft = normalizedValue
        isSaving = true
        defer { isSaving = false }
        if await !commit(normalizedValue.isEmpty ? nil : normalizedValue) {
            draft = normalized(value)
        }
    }

    private func normalized(_ codes: [String]?) -> [String] {
        var seen = Set<String>()
        return (codes ?? []).compactMap { code in
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }

            return trimmed
        }
    }
}

/// A label + menu picker row that commits as soon as a new choice is made.
struct EditablePickerRow: View {
    let label: String
    let value: String
    /// The choices, as (tag, display title) pairs.
    let options: [(value: String, title: String)]
    let commit: (String) async -> Bool

    @State private var draft: String
    @State private var isSaving = false

    init(
        label: String,
        value: String,
        options: [(value: String, title: String)],
        commit: @escaping (String) async -> Bool
    ) {
        self.label = label
        self.value = value
        self.options = options
        self.commit = commit
        _draft = State(initialValue: value)
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Picker(label, selection: $draft) {
                    ForEach(options, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: draft) { old, new in
                    guard !old.isEmpty else { return }

                    Task { await save(new) }
                }
                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in draft = newValue }
    }

    private func save(_ newValue: String) async {
        guard newValue != value, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }
        if await !commit(newValue) {
            draft = value
        }
    }
}

/// A label + switch row that commits as soon as it is toggled.
struct EditableToggleRow: View {
    let label: String
    let value: Bool
    let commit: (Bool) async -> Bool

    @State private var draft = false
    @State private var isSaving = false
    @State private var appeared = false

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Toggle(label, isOn: $draft)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: draft) { _, new in
                        guard appeared else { return }

                        Task { await save(new) }
                    }
                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .onAppear {
            draft = value
            appeared = true
        }
        .onChange(of: value) { _, newValue in draft = newValue }
    }

    private func save(_ newValue: Bool) async {
        guard newValue != value, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }
        if await !commit(newValue) {
            draft = value
        }
    }
}

/// A label + date picker row that commits as soon as a new date is chosen.
struct EditableDateRow: View {
    let label: String
    let value: Date
    let commit: (Date) async -> Bool

    @State private var draft = Date.distantPast
    @State private var isSaving = false

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                DatePicker(label, selection: $draft)
                    .labelsHidden()
                    .onChange(of: draft) { _, new in
                        guard draft != .distantPast else { return }

                        Task { await save(new) }
                    }
                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in draft = newValue }
    }

    private func save(_ newValue: Date) async {
        guard newValue != value, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }
        if await !commit(newValue) {
            draft = value
        }
    }
}

/// A long-form text block that displays read-only until its hover pencil is clicked, then
/// becomes a text editor with Save/Cancel — PadBuddy's `InlineEditableText`, ported for
/// notes and problem statements.
struct InlineEditableText: View {
    let text: String
    var placeholder: LocalizedStringKey = "Empty"
    var rendersHTML = false
    /// Persists the new value; returns whether it saved (failure keeps the editor open).
    let commit: (String) async -> Bool

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isSaving = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                display
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var display: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if text.isEmpty {
                    Text(placeholder).foregroundStyle(.tertiary)
                } else if rendersHTML {
                    HighlightedHTMLText(html: text)
                } else {
                    Text(text)
                        .textSelection(.enabled)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                draft = text
                isEditing = true
                isFocused = true
            } label: {
                Image(systemName: "pencil")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
            .help("Edit")
            .accessibilityLabel("Edit")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .font(.callout)
                .frame(minHeight: 90)
                .focused($isFocused)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { isEditing = false }
                Button {
                    Task { await saveDraft() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    private func saveDraft() async {
        isSaving = true
        defer { isSaving = false }
        if await commit(draft.trimmingCharacters(in: .whitespacesAndNewlines)) {
            isEditing = false
        }
    }
}

/// A label + stepper-less numeric field row that commits on submit or focus loss.
/// Blank commits as nil when `allowsEmpty`, otherwise reverts.
struct EditableNumberRow: View {
    let label: String
    let value: Int?
    let commit: (Int?) async -> Bool

    @State private var draft = ""
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    private var displayValue: String {
        value.map(String.init) ?? ""
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(label, text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .frame(maxWidth: 80)
                    .focused($isFocused)
                    .onSubmit { Task { await save() } }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { Task { await save() } }
                    }
                if isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .onAppear { draft = displayValue }
        .onChange(of: displayValue) { _, newValue in draft = newValue }
    }

    private func save() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != displayValue, !isSaving else { return }
        guard trimmed.isEmpty || Int(trimmed) != nil else {
            draft = displayValue
            return
        }

        isSaving = true
        defer { isSaving = false }
        if await !commit(trimmed.isEmpty ? nil : Int(trimmed)) {
            draft = displayValue
        }
    }
}
