import SwiftUI

/// "+ Add ▾" accessory for a provider group's title row. While a login is in
/// flight it turns into a spinner (with Cancel for Codex).
struct AddAccountMenu: View {
    let provider: AIProviderType
    /// Drives the inline "Add current login" confirm rendered by the group body.
    @Binding var showingAddConfirm: Bool
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if isLoggingIn {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for browser login...")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                if provider == .codex {
                    Button("Cancel") { appState.cancelCodexLogin() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.brand)
                        .focusable(false)
                }
            }
        } else {
            Menu {
                if provider != .codex {
                    Button("Log in new account…") {
                        Task { await appState.loginNewAccount() }
                    }
                    Button("Add current login") {
                        withAnimation { showingAddConfirm = true }
                    }
                } else {
                    Button("Log in new account…") {
                        Task { await appState.loginNewCodexAccount() }
                    }
                    Button("Import current Codex login") {
                        Task { await appState.importCurrentCodexLogin() }
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.caption.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)
            .disabled(appState.isCredentialActionBusy || !isAvailable)
        }
    }

    private var isLoggingIn: Bool {
        provider == .codex ? appState.isLoggingInCodex : appState.isLoggingIn
    }

    private var isAvailable: Bool {
        provider == .codex ? appState.codexAvailable : appState.claudeAvailable
    }
}

/// Inline confirm for capturing the currently logged-in Claude Code account.
struct AddCurrentLoginConfirm: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            Text("This will capture the currently logged-in Claude Code account.")
                .font(.caption)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Cancel") {
                    withAnimation { isPresented = false }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Add Account") {
                    isPresented = false
                    Task { await appState.addAccount() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
                .controlSize(.small)
                .disabled(appState.isCredentialActionBusy)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
