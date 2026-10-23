import SwiftUI

/// Label-editor and removal state shared by an account's `⋯` menu, its context
/// menu and its inline name editor. The host view owns one per account.
@MainActor
final class AccountActionsModel: ObservableObject {
    @Published var isEditingLabel = false
    @Published var editingLabel = ""
    @Published var pendingCodexRemoval = false
}

/// Trailing `⋯` button with every per-account action. Pair it with
/// `.accountActions(account:model:)` on the host so the context menu, the
/// Codex removal confirmation and the inline editor share the same state.
struct AccountActionsMenu: View {
    let account: Account
    @ObservedObject var model: AccountActionsModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Menu {
            AccountActionItems(account: account, model: model)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .frame(width: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
    }
}

/// The menu entries, shared by the `⋯` button and the context menu.
private struct AccountActionItems: View {
    let account: Account
    @ObservedObject var model: AccountActionsModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Edit label") {
            model.editingLabel = account.customLabel ?? ""
            model.isEditingLabel = true
        }
        if account.provider == .claudeCode {
            Button("Re-authenticate (fix stale token)") {
                Task { await appState.reauthenticateAccount(account) }
            }
            .disabled(appState.isCredentialActionBusy)
            Button("Open Claude desktop as this account") {
                Task { await appState.openClaudeDesktop(as: account) }
            }
            .disabled(appState.isCredentialActionBusy || appState.isSwitching)
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
            // Codex logins are only stored in Tagteam's keychain, so removal asks first.
            if account.provider == .codex {
                model.pendingCodexRemoval = true
            } else {
                appState.removeAccount(account)
            }
        }
        .disabled(appState.isCredentialActionBusy)
    }
}

/// Inline label editor; show it in place of the account name while `model.isEditingLabel`.
struct AccountLabelEditor: View {
    let account: Account
    @ObservedObject var model: AccountActionsModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            TextField("Custom label", text: $model.editingLabel)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit(commit)
            Button(action: commit) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .focusable(false)
            Button { model.isEditingLabel = false } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.textSecondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }

    private func commit() {
        appState.updateAccountLabel(account, label: model.editingLabel)
        model.isEditingLabel = false
    }
}

private struct AccountActionsHost: ViewModifier {
    let account: Account
    @ObservedObject var model: AccountActionsModel
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .contextMenu { AccountActionItems(account: account, model: model) }
            .confirmationDialog("Remove Codex account?", isPresented: $model.pendingCodexRemoval) {
                Button("Remove", role: .destructive) { appState.removeAccount(account) }
                    .disabled(appState.isCredentialActionBusy)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Remove this Codex account? Its stored login is deleted from Tagteam.")
            }
    }
}

extension View {
    /// Adds the account context menu and the Codex removal confirmation.
    func accountActions(account: Account, model: AccountActionsModel) -> some View {
        modifier(AccountActionsHost(account: account, model: model))
    }
}
