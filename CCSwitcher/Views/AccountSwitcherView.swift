import SwiftUI

/// Lists all configured accounts with switching and management.
struct AccountSwitcherView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("showFullEmail") private var showFullEmail = false
    @State private var showingAddConfirm = false
    @State private var editingAccountId: UUID?
    @State private var editingLabel = ""
    @State private var pendingCodexRemoval: Account?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if appState.accounts.isEmpty {
                        emptyState
                    } else {
                        providerSection(.claudeCode, title: "Claude Code")
                        if appState.codexAvailable || !appState.accounts(for: .codex).isEmpty {
                            providerSection(.codex, title: "Codex")
                        }
                    }
                }
                .padding(16)
            }
            .confirmationDialog(
                "Remove Codex account?",
                isPresented: Binding(get: { pendingCodexRemoval != nil }, set: { if !$0 { pendingCodexRemoval = nil } }),
                presenting: pendingCodexRemoval
            ) { account in
                Button("Remove", role: .destructive) {
                    appState.removeAccount(account)
                    pendingCodexRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingCodexRemoval = nil }
            } message: { _ in
                Text("Remove this Codex account? Its stored login is deleted from CCSwitcher.")
            }

            addAccountButtons
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .padding(.top, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.textSecondary)

            Text("No Accounts")
                .font(.headline)

            Text("Add your current Claude Code account to get started.")
                .font(.caption)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Provider Section

    private func providerSection(_ provider: AIProviderType, title: LocalizedStringKey) -> some View {
        let rows = appState.profileAccounts(for: provider)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if provider == .codex {
                    codexAddControl
                }
            }
            if rows.isEmpty {
                Text("No accounts in this scope")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(rows) { account in
                    accountRow(account)
                }
            }
        }
    }

    @ViewBuilder
    private var codexAddControl: some View {
        if appState.isLoggingInCodex {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for browser login...")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
                Button("Cancel") { appState.cancelCodexLogin() }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.brand)
            }
        } else {
            Menu {
                Button("Log in new account") {
                    Task { await appState.loginNewCodexAccount() }
                }
                Button("Import current Codex login") {
                    Task { await appState.importCurrentCodexLogin() }
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!appState.codexAvailable)
        }
    }

    // MARK: - Account Row

    private func isLive(_ account: Account) -> Bool {
        appState.activeAccount(for: account.provider)?.id == account.id
    }

    private func accountRow(_ account: Account) -> some View {
        let live = isLive(account)
        return HStack(spacing: 12) {
            // Provider icon
            Image(systemName: account.provider.iconName)
                .font(.title2)
                .foregroundStyle(live ? .brand : .secondary)
                .frame(width: 32, height: 32)

            // Account info
            VStack(alignment: .leading, spacing: 2) {
                if editingAccountId == account.id {
                    HStack(spacing: 4) {
                        TextField("Custom label", text: $editingLabel)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .onSubmit { commitLabelEdit(account) }

                        Button {
                            commitLabelEdit(account)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)

                        Button {
                            editingAccountId = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(account.effectiveDisplayName(obfuscated: !showFullEmail))
                            .font(.subheadline.weight(.medium))

                        Button {
                            editingLabel = account.customLabel ?? ""
                            editingAccountId = account.id
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit label")

                        if live {
                            Badge(text: String(localized: "Active", bundle: L10n.bundle), color: .green)
                        }
                    }
                }

                Text(account.displayEmail(obfuscated: !showFullEmail))
                    .font(.caption)
                    .foregroundStyle(.textSecondary)

                HStack(spacing: 8) {
                    if let sub = account.displaySubscriptionType {
                        Label(sub, systemImage: "creditcard")
                            .font(.caption2)
                            .foregroundStyle(.textSecondary)
                    }
                    Text(account.provider.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.textSecondary)
                }
            }

            Spacer()

            // Actions
            if !live {
                Button("Switch") {
                    Task { await appState.switchTo(account) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.brand)
                .disabled(appState.isAccountActionBusy)
            }

            if account.provider == .claudeCode {
                Button {
                    Task { await appState.reauthenticateAccount(account) }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Re-authenticate (fix stale token)")
            }

            Button {
                requestRemoval(account)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(appState.isAccountActionBusy)
            .help("Remove account")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(live ? .cardFillStrong : .clear)
                .strokeBorder(.cardBorder, lineWidth: 1)
                .shadow(color: AppStyle.cardShadowColor, radius: AppStyle.cardShadowRadius, x: 0, y: AppStyle.cardShadowY)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .contextMenu { accountMenu(account) }
    }

    @ViewBuilder
    private func accountMenu(_ account: Account) -> some View {
        Button("Edit label") {
            editingLabel = account.customLabel ?? ""
            editingAccountId = account.id
        }
        if account.provider == .claudeCode {
            Button(account.isExcludedFromAutoSwitch ? "Include in auto-switch" : "Exclude from auto-switch") {
                appState.setExcludedFromAutoSwitch(account, excluded: !account.isExcludedFromAutoSwitch)
            }
        }
        if !appState.profiles.isEmpty {
            let memberOf = Set(appState.profiles(containing: account).map(\.id))
            Menu("Profiles") {
                ForEach(appState.profiles) { profile in
                    Toggle(profile.name, isOn: Binding(
                        get: { memberOf.contains(profile.id) },
                        set: { appState.setAccount(account, in: profile, included: $0) }
                    ))
                }
            }
        }
        Divider()
        Button("Remove account", role: .destructive) {
            requestRemoval(account)
        }
        .disabled(appState.isAccountActionBusy)
    }

    /// Codex logins are only stored in CCSwitcher's keychain, so removal asks first.
    private func requestRemoval(_ account: Account) {
        if account.provider == .codex {
            pendingCodexRemoval = account
        } else {
            appState.removeAccount(account)
        }
    }

    private func commitLabelEdit(_ account: Account) {
        appState.updateAccountLabel(account, label: editingLabel)
        editingAccountId = nil
    }

    // MARK: - Add Account Buttons

    @ViewBuilder
    private var addAccountButtons: some View {
        if appState.isLoggingIn {
            // Logging in state
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for browser login...")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                Text("Complete the login in your browser, then return here.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.cardFillStrong)
                    .strokeBorder(.cardBorder, lineWidth: 1)
                    .shadow(color: AppStyle.cardShadowColor, radius: AppStyle.cardShadowRadius, x: 0, y: AppStyle.cardShadowY)
            )
        } else if showingAddConfirm {
            // Inline confirmation for "Add Current"
            VStack(spacing: 8) {
                Text("This will capture the currently logged-in Claude Code account.")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        withAnimation { showingAddConfirm = false }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Add Account") {
                        showingAddConfirm = false
                        Task { await appState.addAccount() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.cardFillStrong)
                    .strokeBorder(.cardBorder, lineWidth: 1)
                    .shadow(color: AppStyle.cardShadowColor, radius: AppStyle.cardShadowRadius, x: 0, y: AppStyle.cardShadowY)
            )
        } else {
            VStack(spacing: 8) {
                // Primary: Login new account via browser
                Button {
                    Task { await appState.loginNewAccount() }
                } label: {
                    Label("Login New Account", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppStyle.buttonTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                // Secondary: Capture already-logged-in account
                Button {
                    withAnimation { showingAddConfirm = true }
                } label: {
                    Label("Add Current Account", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    colorScheme == .dark
                                        ? Color.gray.opacity(0.4)
                                        : Color.white.opacity(0.22),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
