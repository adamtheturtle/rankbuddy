import BuddyAppKit
import SwiftUI

/// A form for adding or editing a HackerRank account: label, personal access token, and
/// an optional region/base-URL override, with a button to validate the token against the
/// API before saving.
struct AccountEditor: View {
    /// The progress of a token-validation attempt.
    enum ValidationState: Equatable {
        case idle
        case validating
        case valid
        case invalid(String)
    }

    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The account being edited, or `nil` when adding a new one.
    let existing: Account?

    @State private var label: String
    @State private var token: String
    @State private var baseURLOverride: String
    @State private var validation: ValidationState = .idle

    init(existing: Account? = nil) {
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        _token = State(initialValue: existing?.token ?? "")
        _baseURLOverride = State(initialValue: existing?.baseURLOverride ?? "")
    }

    var body: some View {
        Form {
            Section("Account") {
                TextField("Label", text: $label)
                SecureField("Personal access token", text: $token)
                TextField("Base URL (optional)", text: $baseURLOverride)
            }

            Section {
                Button("Validate token") {
                    Task { await validate() }
                }
                .disabled(trimmedToken.isEmpty || validation == .validating)

                validationStatus
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .navigationTitle(existing == nil ? "Add Account" : "Edit Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    @ViewBuilder private var validationStatus: some View {
        switch validation {
        case .idle:
            EmptyView()

        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Validating…").foregroundStyle(.secondary)
            }

        case .valid:
            Label("Token is valid — connected to \(draft.baseURL.host() ?? "HackerRank")",
                  systemImage: "checkmark.circle")
                .foregroundStyle(.green)

        case let .invalid(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOverride: String {
        baseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedLabel.isEmpty && !trimmedToken.isEmpty && validation != .validating
    }

    /// The account assembled from the current field values, reusing the edited account's
    /// id so an edit updates rather than duplicates.
    private var draft: Account {
        Account(
            label: trimmedLabel,
            token: trimmedToken,
            baseURLOverride: trimmedOverride.isEmpty ? nil : trimmedOverride,
            id: existing?.id ?? UUID()
        )
    }

    private func validate() async {
        validation = .validating
        do {
            try await HackerRankClient(account: draft).validateToken()
            validation = .valid
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            validation = .invalid(message)
        }
    }

    private func save() {
        if existing == nil {
            store.add(draft)
        } else {
            store.update(draft)
        }
        dismiss()
    }
}
