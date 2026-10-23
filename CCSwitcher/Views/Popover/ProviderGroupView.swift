import SwiftUI

/// One provider's group card: the live account with its limits, then the other
/// in-scope accounts as rows. Used for Claude Code and Codex.
struct ProviderGroupView: View {
    let provider: AIProviderType

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var menuBarConfig: MenuBarConfig
    @AppStorage("showFullEmail") private var showFullEmail = false
    @AppStorage("codexRestartAppServer") private var restartsAppServer = true
    @State private var showingAddConfirm = false
    @State private var showAllRows = false
    @State private var isSwitchingLive = false
    @StateObject private var liveActions = AccountActionsModel()

    private static let visibleRowLimit = 5

    private var entry: AppState.PopoverAccount? {
        appState.popoverAccount(for: provider)
    }

    private var otherAccounts: [Account] {
        let cardId = entry?.account.id
        return appState.profileAccounts(for: provider).filter { $0.id != cardId }
    }

    private var title: LocalizedStringKey {
        provider == .codex ? "Codex" : "Claude Code"
    }

    var body: some View {
        GroupCard(title, systemImage: provider.iconName) {
            AddAccountMenu(provider: provider, showingAddConfirm: $showingAddConfirm)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if provider == .claudeCode && !appState.claudeAvailable {
                    cliUnavailable
                } else {
                    groupBody
                }
            }
        }
    }

    @ViewBuilder
    private var groupBody: some View {
        if showingAddConfirm && provider == .claudeCode {
            AddCurrentLoginConfirm(isPresented: $showingAddConfirm)
                .padding(.bottom, AppStyle.rowVerticalPadding)
        }

        if let entry {
            liveBlock(entry)
            let rows = otherAccounts
            let shown = showAllRows ? rows : Array(rows.prefix(Self.visibleRowLimit))
            ForEach(shown) { account in
                GroupDivider()
                AccountRowView(account: account)
            }
            if rows.count > Self.visibleRowLimit {
                Button {
                    withAnimation { showAllRows.toggle() }
                } label: {
                    Text(showAllRows
                        ? String(localized: "Show less", bundle: L10n.bundle)
                        : String(localized: "Show \(rows.count - Self.visibleRowLimit) more", bundle: L10n.bundle))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.brand)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.top, AppStyle.rowVerticalPadding)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Empty and unavailable states

    @ViewBuilder
    private var emptyState: some View {
        if provider == .codex && appState.accounts(for: .codex).isEmpty {
            // Codex installed, nothing added yet.
            VStack(alignment: .leading, spacing: 8) {
                Text("Add your Codex account")
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    Button("Log in") {
                        Task { await appState.loginNewCodexAccount() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.brand)
                    Button("Import current") {
                        Task { await appState.importCurrentCodexLogin() }
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .focusable(false)
                .disabled(appState.isCredentialActionBusy || !appState.codexAvailable)
            }
        } else {
            HStack {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.textSecondary)
                Spacer(minLength: 8)
                if provider == .claudeCode {
                    Button("Log in…") {
                        Task { await appState.loginNewAccount() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                    .disabled(appState.isCredentialActionBusy)
                }
            }
        }
    }

    private var emptyText: String {
        let inProfile = appState.activeProfileId != nil
        if provider == .codex {
            return inProfile
                ? String(localized: "No Codex accounts in this profile", bundle: L10n.bundle)
                : String(localized: "No Codex accounts yet", bundle: L10n.bundle)
        }
        return inProfile
            ? String(localized: "No Claude Code accounts in this profile", bundle: L10n.bundle)
            : String(localized: "No Claude Code accounts yet", bundle: L10n.bundle)
    }

    private var cliUnavailable: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
            Text("Claude CLI not found")
                .font(.callout)
                .foregroundStyle(.textSecondary)
            Spacer(minLength: 8)
            Button("Set up…") { SettingsDeepLink.open("claudeCLI") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .focusable(false)
        }
    }

    // MARK: - Live block

    private func liveBlock(_ entry: AppState.PopoverAccount) -> some View {
        let account = entry.account
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.isLive ? "circle.fill" : "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(entry.isLive ? .green : .textSecondary)
                if liveActions.isEditingLabel {
                    AccountLabelEditor(account: account, model: liveActions)
                } else {
                    Text(account.effectiveDisplayName(obfuscated: !showFullEmail))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if !entry.isLive {
                        Badge(text: String(localized: "Not live", bundle: L10n.bundle), color: .gray)
                    } else if !entry.isInScope {
                        Badge(text: String(localized: "Not in this profile", bundle: L10n.bundle), color: .gray)
                    }
                    if let sub = account.displaySubscriptionType {
                        Badge(text: sub, color: .brand)
                    }
                }
                if !entry.isLive {
                    switchButton(account)
                }
                AccountActionsMenu(account: account, model: liveActions)
            }
            if account.customLabel != nil {
                Text(account.displayEmail(obfuscated: !showFullEmail))
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if provider == .codex {
                codexLimits(account)
            } else {
                claudeLimits(account)
            }
        }
        .padding(.bottom, otherAccounts.isEmpty ? 0 : AppStyle.rowVerticalPadding)
        .accountActions(account: account, model: liveActions)
    }

    private func switchButton(_ account: Account) -> some View {
        Button {
            isSwitchingLive = true
            Task {
                await appState.switchTo(account)
                isSwitchingLive = false
            }
        } label: {
            if isSwitchingLive {
                ProgressView().controlSize(.small)
                    .frame(minWidth: 40)
            } else {
                Text("Switch")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.brand)
        .focusable(false)
        .disabled(appState.isCredentialActionBusy)
    }

    @ViewBuilder
    private func claudeLimits(_ account: Account) -> some View {
        let usage = appState.accountUsage[account.id]
        if let usage, usage.fiveHour != nil || usage.sevenDay != nil {
            if let w = usage.fiveHour {
                limitRow(label: "5h", utilization: w.utilization, kind: .session, reset: w.resetsAtDate.map(resetCountdownString(until:)))
            }
            if let w = usage.sevenDay {
                limitRow(label: "7d", utilization: w.utilization, kind: .weekly, reset: w.resetsAtDate.map(resetCountdownString(until:)))
            }
            extraUsageRow(usage.extraUsage)
            staleHint(appState.accountUsageSampledAt[account.id])
        } else {
            statusLine(appState.accountUsageErrors[account.id], account: account)
        }
    }

    @ViewBuilder
    private func codexLimits(_ account: Account) -> some View {
        let usage = appState.codexUsage[account.id]
        let error = appState.codexUsageErrors[account.id]
        if let usage, usage.primary != nil || usage.secondary != nil {
            if let w = usage.primary {
                limitRow(label: w.limitLabel(fallback: "5h"), utilization: w.usedPercent, kind: w.limitKind(fallback: .session), reset: w.resetsAt.map(resetCountdownString(until:)))
            }
            if let w = usage.secondary {
                limitRow(label: w.limitLabel(fallback: "7d"), utilization: w.usedPercent, kind: w.limitKind(fallback: .weekly), reset: w.resetsAt.map(resetCountdownString(until:)))
            }
            staleHint(appState.codexUsageSampledAt[account.id])
        } else {
            statusLine(error, account: account, expiredText: String(localized: "Waiting for the Codex CLI to refresh its session", bundle: L10n.bundle))
        }

        if error != nil || appState.errorMessage == CodexServiceError.unmanagedLogin(email: nil).localizedDescription {
            Button { SettingsDeepLink.open("codex") } label: {
                Text("Open Codex settings")
                    .font(.caption)
                    .foregroundStyle(.brand)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }

        if appState.runningCodexSessions > 0 {
            notice(appState.runningCodexSessions == 1
                ? "1 Codex session running — restart it to use the switched account"
                : "\(appState.runningCodexSessions) Codex sessions running — restart them to use the switched account")
        }

        if (appState.codexAppServerRunning || appState.codexDesktopRunning) && !restartsAppServer {
            notice("Codex app-server or ChatGPT (Codex) running — they keep the previous account until restarted")
        }
    }

    // MARK: - Pieces

    private func notice(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "info.circle")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.textSecondary)
    }

    /// A missing reading is never drawn as 0%: `LimitBar` shows a neutral track and an em dash.
    private func limitRow(label: String, utilization: Double?, kind: LimitBarKind, reset: String?) -> some View {
        LimitBar(
            label: label,
            utilization: utilization,
            color: utilization.map { menuBarConfig.limitBarColor(for: kind, utilization: $0, context: .dashboard) } ?? .clear,
            reset: reset
        )
    }

    @ViewBuilder
    private func extraUsageRow(_ extra: ExtraUsage?) -> some View {
        if let extra {
            let enabled = extra.isEnabled == true
            let color: Color = enabled ? .orange : .gray
            HStack(spacing: 6) {
                Image(systemName: enabled ? "bolt.fill" : "bolt.slash")
                    .font(.caption)
                    .foregroundStyle(color)
                Text("Extra usage")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                Spacer()
                Text(LocalizedStringKey(enabled ? "On" : "Off"))
                    .font(.caption)
                    .foregroundStyle(color)
            }
        }
    }

    @ViewBuilder
    private func staleHint(_ sampledAt: Date?) -> some View {
        if let sampledAt, Date().timeIntervalSince(sampledAt) >= 90 {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text("Updated \(Text(sampledAt, style: .relative)) ago")
            }
            .font(.caption)
            .foregroundStyle(.textSecondary)
        }
    }

    @ViewBuilder
    private func statusLine(_ error: AppState.UsageErrorState?, account: Account, expiredText: String? = nil) -> some View {
        if let error {
            let text = error.isExpired
                ? (expiredText ?? String(localized: "Session expired — re-login", bundle: L10n.bundle))
                : error.message
            HStack(spacing: 6) {
                Image(systemName: error.isRateLimited ? "timer" : (error.isExpired ? "exclamationmark.triangle" : "xmark.circle"))
                    .font(.caption)
                    .foregroundStyle(error.isExpired ? .yellow : .red)
                HoverTip(text) {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if error.isExpired && account.provider == .claudeCode {
                    Button("Re-login") {
                        Task { await appState.reauthenticateAccount(account) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                    .disabled(appState.isCredentialActionBusy)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Waiting for usage data...")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                Spacer()
            }
        }
    }
}
