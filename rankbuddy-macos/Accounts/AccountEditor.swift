//
//  AccountEditor.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyDesignSystem
import SwiftUI

/// A form for adding or editing a HackerRank account: label, personal access token, and
/// an optional region/base-URL override, with a button to validate the token against the
/// API before saving.
struct AccountEditor: View {
    @Environment(AccountStore.self) private var store
    @Environment(AccountHealthMonitor.self) private var health
    @Environment(\.dismiss) private var dismiss

    /// The account being edited, or `nil` when adding a new one.
    let existing: Account?
    /// Whether the editor is hosted inline in a master-detail pane (#71) rather than a modal
    /// sheet. When embedded it renders its own Save/Cancel buttons instead of sheet toolbar
    /// items and reports completion through `onFinish` rather than dismissing.
    let embedded: Bool
    /// Called when an embedded editor finishes: the saved account's id on save, or `nil` when
    /// the user cancels. Ignored (and `nil`) for the sheet presentation, which dismisses instead.
    let onFinish: ((Account.ID?) -> Void)?

    @State private var label: String
    @State private var token: String
    @State private var baseURLOverride: String
    @State private var userEmail: String
    @State private var selectedIcon: String
    @State private var selectedTintHex: String?
    /// Validation progress, using buddy-kit's shared credential-validation state (#2).
    @State private var validation: CredentialValidationState = .idle
    /// Whether the token is shown in clear text (#48), gated behind Touch ID when enabled.
    @State private var isTokenRevealed = false

    init(existing: Account? = nil, embedded: Bool = false, onFinish: ((Account.ID?) -> Void)? = nil) {
        self.existing = existing
        self.embedded = embedded
        self.onFinish = onFinish
        _label = State(initialValue: existing?.label ?? "")
        _token = State(initialValue: existing?.token ?? "")
        _baseURLOverride = State(initialValue: existing?.baseURLOverride ?? "")
        _userEmail = State(initialValue: existing?.userEmail ?? "")
        _selectedIcon = State(initialValue: existing?.displayIcon ?? Account.defaultIconSymbol)
        _selectedTintHex = State(initialValue: existing?.tintHex)
    }

    var body: some View {
        Form {
            Section {
                TextField("Label", text: $label)
                HStack {
                    if isTokenRevealed {
                        TextField("Personal access token", text: $token)
                    } else {
                        SecureField("Personal access token", text: $token)
                    }
                    Button(isTokenRevealed ? "Hide" : "Reveal") { toggleReveal() }
                        .buttonStyle(.link)
                }
                TextField("Base URL (optional)", text: $baseURLOverride)
            } header: {
                Text("Account")
            } footer: {
                GetAPIKeyLink()
            }

            Section {
                TextField("Your email (optional)", text: $userEmail)
                    .textContentType(.emailAddress)
                if !emailLooksValid {
                    Label("That doesn’t look like an email address.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("The email this token belongs to. Used to highlight items owned by or " +
                    "assigned to you.")
            }

            AccountAppearancePicker(selectedIcon: $selectedIcon, selectedTintHex: $selectedTintHex)

            Section {
                Button("Validate token") {
                    Task { await validate() }
                }
                .disabled(trimmedToken.isEmpty || validation == .validating)

                ValidationStatusBanner(
                    validation,
                    validating: "Validating…",
                    success: "Token is valid: connected to \(draft.baseURL.host() ?? "HackerRank")"
                )
            }

            // When embedded in the master-detail pane there's no sheet toolbar, so the editor
            // carries its own Save/Cancel buttons (#71).
            if embedded {
                Section {
                    HStack {
                        Button("Cancel") { onFinish?(nil) }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button(existing == nil ? "Add Account" : "Save Changes") { save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSave)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: embedded ? nil : 440)
        .navigationTitle(existing == nil ? "Add Account" : "Edit Account")
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
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

    private var trimmedEmail: String {
        userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the email is blank (it's optional) or looks plausible. A non-empty,
    /// implausible address blocks saving so a typo doesn't silently persist.
    private var emailLooksValid: Bool {
        trimmedEmail.isEmpty || EmailValidation.isLikelyValid(trimmedEmail)
    }

    private var canSave: Bool {
        !trimmedLabel.isEmpty && !trimmedToken.isEmpty && validation != .validating && emailLooksValid
    }

    /// The account assembled from the current field values, reusing the edited account's
    /// id so an edit updates rather than duplicates.
    private var draft: Account {
        Account(
            label: trimmedLabel,
            token: trimmedToken,
            baseURLOverride: trimmedOverride.isEmpty ? nil : trimmedOverride,
            userEmail: trimmedEmail.isEmpty ? nil : trimmedEmail,
            // Store the default icon as nil to keep older-style accounts clean.
            iconSymbol: selectedIcon == Account.defaultIconSymbol ? nil : selectedIcon,
            tintHex: selectedTintHex,
            id: existing?.id ?? UUID()
        )
    }

    /// Reveals the token (challenging Touch ID first when that's enabled) or hides it again.
    private func toggleReveal() {
        if isTokenRevealed {
            isTokenRevealed = false
        } else {
            Task {
                isTokenRevealed = await BiometricGate.authenticateForReveal(
                    settingEnabled: UserDefaults.standard.bool(forKey: BiometricAuth.revealSettingKey),
                    reason: "reveal your token"
                )
            }
        }
    }

    private func validate() async {
        validation = .validating
        do {
            let client = HackerRankClient(account: draft)
            try await client.validateToken()
            validation = .valid
            // Auto-discover the signed-in user's email (#72) when the field is blank, so identity
            // is captured without hand-entry. Best-effort: a lookup failure never fails validation,
            // and the field stays editable as the fallback.
            if trimmedEmail.isEmpty, let user = try? await client.currentUser(), !user.email.isEmpty {
                userEmail = user.email
            }
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
        // The token may have just been fixed; clear any stale "rejected" verdict so the
        // banner drops immediately (a later health check re-flags it if it's still bad).
        health.clearUnauthorized(draft.id)
        if let onFinish {
            onFinish(draft.id)
        } else {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AccountEditor()
            .environment(AccountStore.rankBuddy(isTesting: true))
            .environment(AccountHealthMonitor())
    }
}
