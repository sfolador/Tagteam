import SwiftUI

/// Left popover column: Claude Code and Codex account groups.
/// No ScrollView: the shell owns scrolling.
struct AccountsColumnView: View {
    @EnvironmentObject private var appState: AppState

    private var showsCodexGroup: Bool {
        appState.codexAvailable || !appState.accounts(for: .codex).isEmpty
    }

    var body: some View {
        VStack(spacing: AppStyle.groupSpacing) {
            if appState.accounts.isEmpty {
                onboarding
            } else {
                ProviderGroupView(provider: .claudeCode)
                if showsCodexGroup {
                    ProviderGroupView(provider: .codex)
                }
            }
        }
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        GroupCard("Get started", systemImage: "person.crop.circle.badge.plus") {
            VStack(spacing: 10) {
                Text("Add your Claude Code account to get started.")
                    .font(.callout)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await appState.loginNewAccount() }
                } label: {
                    Text("Log in with browser").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)

                Button {
                    Task { await appState.addAccount() }
                } label: {
                    Text("Add current login").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if appState.codexAvailable {
                    Button {
                        Task { await appState.loginNewCodexAccount() }
                    } label: {
                        Text("Add Codex account").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.regular)
            .focusable(false)
            .disabled(appState.isCredentialActionBusy)
            .frame(maxWidth: .infinity)
            // Loading the first account list: placeholder, never a flash of buttons.
            .redacted(reason: appState.isLoading ? .placeholder : [])
        }
    }
}
