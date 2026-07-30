//
//  AccountEditor.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyDesignSystem
import HackerRankKit
import SwiftUI

// A flat, Mail-style editor for adding or editing a HackerRank account.
// swiftlint:disable:next type_body_length
struct AccountEditor: View {
    @Environment(AccountStore.self) private var store
    @Environment(AccountHealthMonitor.self) private var health
    @Environment(\.dismiss) private var dismiss

    let existing: Account?
    let embedded: Bool
    let onFinish: ((Account.ID?) -> Void)?

    @State private var label: String
    @State private var token: String
    @State private var baseURLOverride: String
    @State private var userEmail: String
    @State private var selectedIcon: String
    @State private var selectedTintHex: String?
    @State private var validation: CredentialValidationState = .idle
    @State private var isTokenRevealed = false
    @State private var scopeWarning: String?
    @State private var validationTask: Task<Void, Never>?
    @State private var validationGeneration = 0

    private let initialToken: String
    private let initialBaseURLOverride: String

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
        initialToken = existing?.token ?? ""
        initialBaseURLOverride = existing?.baseURLOverride ?? ""
    }

    var body: some View {
        editorForm
            .frame(minWidth: embedded ? nil : 460, minHeight: embedded ? nil : 280, alignment: .top)
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
            .onChange(of: token) { _, _ in credentialsChanged() }
            .onChange(of: baseURLOverride) { _, _ in credentialsChanged() }
            .onDisappear { cancelOutstandingWork() }
    }

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            formFields
            validationBanner
            scopeWarningBanner
            actionRow
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldRow("Personal access token") {
                HStack(spacing: 6) {
                    Group {
                        if isTokenRevealed {
                            TextField("", text: $token, prompt: Text("Paste your token"))
                        } else {
                            SecureField("", text: $token, prompt: Text("Paste your token"))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .accessibilityLabel("Personal access token")

                    Button {
                        toggleReveal()
                    } label: {
                        Image(systemName: isTokenRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(isTokenRevealed ? "Hide the token" : "Show the token")
                    .accessibilityLabel(isTokenRevealed ? "Hide token" : "Show token")
                }
            }

            fieldRow("Base URL") {
                TextField("", text: $baseURLOverride, prompt: Text(Account.defaultBaseURL.absoluteString))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Base URL")
                    .help("Override only for regional HackerRank deployments. Leave blank to use the default.")
            }

            if isEditing || isValidated {
                fieldRow("Description") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("", text: $label, prompt: Text(defaultLabel))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Description")
                        if duplicateLabelMessage() != nil {
                            Text("Use a unique description so this account is distinguishable in selectors.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                fieldRow("Icon", alignment: .center) {
                    AccountIconPicker(
                        selectedIcon: $selectedIcon,
                        tint: selectedTintHex.flatMap(Color.init(accountHex:)) ?? .accentColor
                    )
                }

                fieldRow("Color", alignment: .center) {
                    HStack(spacing: 10) {
                        ForEach(AccountAppearance.tints) { option in
                            let color = option.hex.flatMap(Color.init(accountHex:)) ?? Color.accentColor
                            Button {
                                selectedTintHex = option.hex
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        if selectedTintHex == option.hex {
                                            Circle().strokeBorder(.primary, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(option.name)
                            .accessibilityLabel(option.name)
                            .accessibilityAddTraits(
                                selectedTintHex == option.hex ? [.isButton, .isSelected] : .isButton
                            )
                        }
                    }
                }

                fieldRow("") {
                    Button("Reset") {
                        selectedIcon = Account.defaultIconSymbol
                        selectedTintHex = nil
                    }
                    .buttonStyle(.borderless)
                    .help("Use the default icon and color.")
                    .opacity(hasCustomAppearance ? 1 : 0)
                    .disabled(!hasCustomAppearance)
                    .accessibilityHidden(!hasCustomAppearance)
                }
            }

            fieldRow("") {
                VStack(alignment: .leading, spacing: 4) {
                    GetTokenLink()
                        .font(.callout)
                    Text("Requires a HackerRank for Work personal access token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            if !(embedded && isEditing) {
                Button("Cancel", role: .cancel) { cancel() }
                    .keyboardShortcut(.cancelAction)
            }
            validateButton
            if embedded {
                Button(isEditing ? "Save Changes" : "Add Account") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
    }

    @ViewBuilder private var validateButton: some View {
        // Style off "do the credentials still need validating" rather than `canSave`,
        // which flips false *while* validating and made the button flash prominent
        // mid-validation on an already-saveable account.
        if isValidated || credentialsUnchanged {
            Button("Validate") { startValidation() }
                .buttonStyle(.bordered)
                .disabled(validateDisabled)
        } else {
            Button("Validate") { startValidation() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(validateDisabled)
        }
    }

    private func fieldRow(
        _ title: LocalizedStringKey,
        alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: alignment, spacing: 10) {
            Text(title)
                .lineLimit(1)
                .frame(width: 150, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var validationBanner: some View {
        // ValidationStatusBanner resolves to EmptyView when idle (and after a
        // success), and SwiftUI drops layout modifiers around an empty view — so a
        // bare `.frame(minHeight:)` reserved nothing and the action row jumped down
        // when validation started and back up when it finished. Anchor the banner
        // over an always-present clear placeholder to genuinely hold the space.
        ZStack(alignment: .leading) {
            Color.clear.frame(height: 20)
            ValidationStatusBanner(validation, validating: "Validating token...")
        }
    }

    @ViewBuilder private var scopeWarningBanner: some View {
        if let scopeWarning {
            Label(scopeWarning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
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

    private var isEditing: Bool {
        existing != nil
    }

    private var isValidated: Bool {
        if case .valid = validation { return true }
        return false
    }

    private var validateDisabled: Bool {
        trimmedToken.isEmpty || validation == .validating
    }

    private var credentialsUnchanged: Bool {
        isEditing && trimmedToken == initialToken && trimmedOverride == initialBaseURLOverride
    }

    private var canSave: Bool {
        validation != .validating && duplicateLabelMessage() == nil && (isValidated || credentialsUnchanged)
    }

    private var defaultLabel: String {
        if !trimmedEmail.isEmpty { return trimmedEmail }
        let baseURL = URL(string: trimmedOverride) ?? Account.defaultBaseURL
        return baseURL.host() ?? "HackerRank"
    }

    private var hasCustomAppearance: Bool {
        selectedIcon != Account.defaultIconSymbol || selectedTintHex != nil
    }

    private var draft: Account {
        Account(
            label: trimmedLabel.isEmpty ? defaultLabel : trimmedLabel,
            token: trimmedToken,
            baseURLOverride: trimmedOverride.isEmpty ? nil : trimmedOverride,
            userEmail: trimmedEmail.isEmpty ? nil : trimmedEmail,
            iconSymbol: selectedIcon == Account.defaultIconSymbol ? nil : selectedIcon,
            tintHex: selectedTintHex,
            id: existing?.id ?? UUID()
        )
    }

    private func credentialsChanged() {
        guard !credentialsUnchanged else { return }

        validationTask?.cancel()
        validationTask = nil
        validation = .idle
        scopeWarning = nil
    }

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

    private func cancel() {
        cancelOutstandingWork()
        if let onFinish {
            onFinish(nil)
        } else {
            dismiss()
        }
    }

    private func save() {
        cancelOutstandingWork()
        let account = draft
        if existing == nil {
            store.add(account)
        } else {
            store.update(account)
        }
        health.clearUnauthorized(account.id)
        if let onFinish {
            onFinish(account.id)
        } else {
            dismiss()
        }
    }

    private func startValidation() {
        validationTask?.cancel()
        validationGeneration &+= 1
        let generation = validationGeneration
        validationTask = Task {
            await validate()
            if validationGeneration == generation {
                validationTask = nil
            }
        }
    }

    private func cancelOutstandingWork() {
        validationTask?.cancel()
        validationTask = nil
        validationGeneration &+= 1
        isTokenRevealed = false
    }
}

// MARK: - Credential validation

/// Same-file extension so the struct body stays within the lint length budget; `private`
/// state remains accessible from here.
private extension AccountEditor {
    static let allScopesRefusedWarning = "This token reached HackerRank but was refused for tests, " +
        "questions, interviews, people, and teams. It may be expired or scoped too narrowly to be useful."

    struct ValidationFingerprint: Equatable {
        let token: String
        let baseURL: URL
    }

    var currentValidationFingerprint: ValidationFingerprint {
        ValidationFingerprint(token: trimmedToken, baseURL: draft.baseURL)
    }

    func validationStillMatches(_ fingerprint: ValidationFingerprint) -> Bool {
        currentValidationFingerprint == fingerprint
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func validate() async {
        if let demo = Account.DemoMagicKey(typedToken: token) {
            let demoID: Account.ID? = switch demo {
            case .mockData:
                store.addDemoIfMissing()
            case .badKey:
                store.addBadKeyDemoIfMissing()
            }
            if let onFinish {
                onFinish(demoID)
            } else {
                dismiss()
            }
            return
        }

        if draft.hasMalformedBaseURLOverride {
            validation = .invalid(
                "The Base URL isn't a valid web address. Enter a full URL starting with https://, " +
                    "or leave it blank to use the standard HackerRank server."
            )
            return
        }
        if let message = duplicateAccountMessage() {
            validation = .invalid(message)
            return
        }
        if let message = duplicateLabelMessage() {
            validation = .invalid(message)
            return
        }

        let fingerprint = currentValidationFingerprint
        let account = draft
        validation = .validating
        scopeWarning = nil

        do {
            let client = HackerRankClient(account: account)
            try await client.validateToken()
            guard validationStillMatches(fingerprint), !Task.isCancelled else { return }

            let signedInUser = try await currentUser(client: client)
            guard validationStillMatches(fingerprint), !Task.isCancelled else { return }

            userEmail = signedInUser.email
            if trimmedLabel.isEmpty {
                label = defaultLabel
            }

            let warning = await missingScopesWarning(client: client)
            guard validationStillMatches(fingerprint), !Task.isCancelled else { return }

            scopeWarning = warning
            validation = .valid
        } catch {
            guard validationStillMatches(fingerprint), !Task.isCancelled else { return }

            validation = .invalid(friendlyValidationMessage(for: error))
        }
    }

    func currentUser(client: HackerRankClient) async throws -> User {
        try await client.currentUser()
    }

    func duplicateAccountMessage() -> String? {
        let candidate = draft
        let clashes = store.accounts.contains { account in
            account.id != candidate.id
                && account.token.trimmingCharacters(in: .whitespacesAndNewlines) == candidate.token
                && account.serverIdentity == candidate.serverIdentity
        }
        guard clashes else { return nil }

        return "This token is already added as another account. Each account must use a unique token."
    }

    func duplicateLabelMessage() -> String? {
        let candidateLabel = draft.label
        let clashes = store.accounts.contains { account in
            account.id != draft.id && Account.labelsConflict(account.label, candidateLabel)
        }
        guard clashes else { return nil }

        return "Another account already uses this description. Choose a unique description."
    }

    func missingScopesWarning(client: HackerRankClient) async -> String? {
        async let testsOK = endpointAuthorized { _ = try await client.testsPage() }
        async let questionsOK = endpointAuthorized { _ = try await client.questionsPage() }
        async let interviewsOK = endpointAuthorized { _ = try await client.interviewsPage() }
        async let peopleOK = endpointAuthorized { _ = try await client.usersPage() }
        async let teamsOK = endpointAuthorized { _ = try await client.teamsPage() }

        var missing: [String] = []
        if await testsOK == false { missing.append("Tests") }
        if await questionsOK == false { missing.append("Questions") }
        if await interviewsOK == false { missing.append("Interviews") }
        if await peopleOK == false { missing.append("People") }
        if await teamsOK == false { missing.append("Teams") }
        guard !missing.isEmpty else { return nil }

        if missing.count == 5 { return Self.allScopesRefusedWarning }

        return "This token works, but isn't authorized for: \(missing.joined(separator: ", ")). " +
            "Those sections may be empty."
    }

    func endpointAuthorized(_ probe: () async throws -> Void) async -> Bool {
        do {
            try await probe()
            return true
        } catch {
            return !isUnauthorized(error)
        }
    }

    func isUnauthorized(_ error: any Error) -> Bool {
        guard case let HackerRankError.http(status, _) = error else { return false }

        return status == 401 || status == 403
    }

    func friendlyValidationMessage(for error: any Error) -> String {
        if isUnauthorized(error) {
            return "HackerRank rejected this token. Check that it is a valid HackerRank for Work personal access token."
        }
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Couldn't reach HackerRank. Check your internet connection and try again."
        }
        return "Couldn't validate this token. Try again."
    }
}

#Preview {
    NavigationStack {
        AccountEditor()
            .environment(AccountStore.rankBuddy(isTesting: true))
            .environment(AccountHealthMonitor())
    }
} // swiftlint:disable:this file_length
