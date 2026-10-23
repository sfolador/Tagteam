import SwiftUI

/// Live Claude + Codex cards shown under the profile bar.
struct ProviderCardsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var menuBarConfig: MenuBarConfig
    @AppStorage("showFullEmail") private var showFullEmail = false
    @AppStorage("settingsSection") private var settingsSection = ""
    @AppStorage("codexRestartAppServer") private var restartsAppServer = true

    private var claudeAccount: AppState.CardAccount? {
        appState.cardAccount(for: .claudeCode)
    }

    private var codexAccount: AppState.CardAccount? {
        appState.cardAccount(for: .codex)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let entry = claudeAccount {
                claudeCard(entry)
            }
            if let entry = codexAccount {
                codexCard(entry)
            } else if appState.codexAvailable {
                addCodexRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Claude

    private func claudeCard(_ entry: AppState.CardAccount) -> some View {
        let account = entry.account
        let usage = appState.accountUsage[account.id]
        return card(entry) {
            if let usage {
                if let w = usage.fiveHour {
                    limitRow(label: "5h", utilization: w.utilization ?? 0, kind: .session, reset: w.resetTimeString)
                }
                if let w = usage.sevenDay {
                    limitRow(label: "7d", utilization: w.utilization ?? 0, kind: .weekly, reset: w.resetTimeString)
                }
                staleHint(appState.accountUsageSampledAt[account.id])
            } else {
                statusLine(appState.accountUsageErrors[account.id])
            }
        }
    }

    // MARK: - Codex

    private func codexCard(_ entry: AppState.CardAccount) -> some View {
        let account = entry.account
        let usage = appState.codexUsage[account.id]
        let error = appState.codexUsageErrors[account.id]
        return card(entry) {
            if let usage, usage.primary != nil || usage.secondary != nil {
                if let w = usage.primary {
                    limitRow(label: "5h", utilization: w.usedPercent, kind: .session, reset: w.resetsAt.map(resetCountdownString(until:)))
                }
                if let w = usage.secondary {
                    limitRow(label: "7d", utilization: w.usedPercent, kind: .weekly, reset: w.resetsAt.map(resetCountdownString(until:)))
                }
                staleHint(appState.codexUsageSampledAt[account.id])
            } else {
                statusLine(error, expiredText: String(localized: "Waiting for the Codex CLI to refresh its session", bundle: L10n.bundle))
            }

            if error != nil || appState.errorMessage == CodexServiceError.unmanagedLogin(email: nil).localizedDescription {
                Button(action: openCodexSettings) {
                    Text("Open Codex settings")
                        .font(.caption2)
                        .foregroundStyle(.brand)
                }
                .buttonStyle(.plain)
            }

            if appState.runningCodexSessions > 0 {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text(appState.runningCodexSessions == 1
                        ? "1 Codex session running — restart it to use the switched account"
                        : "\(appState.runningCodexSessions) Codex sessions running — restart them to use the switched account")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.textSecondary)
            }

            if (appState.codexAppServerRunning || appState.codexDesktopRunning) && !restartsAppServer {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Codex app-server or ChatGPT (Codex) running — they keep the previous account until restarted")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.textSecondary)
            }
        }
    }

    private var addCodexRow: some View {
        Button {
            Task { await appState.loginNewCodexAccount() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: AIProviderType.codex.iconName)
                    .font(.caption)
                Text("Add Codex account")
                    .font(.caption)
                Spacer()
                if appState.isLoggingInCodex {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
            }
            .foregroundStyle(.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                    .strokeBorder(.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(appState.isLoggingInCodex)
    }

    // MARK: - Pieces

    private func openCodexSettings() {
        settingsSection = "codex"
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .ccswitcherOpenSettings, object: nil)
    }

    private func card<Content: View>(_ entry: AppState.CardAccount, @ViewBuilder content: () -> Content) -> some View {
        let account = entry.account
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: account.provider.iconName)
                    .font(.caption)
                    .foregroundStyle(.brand)
                Text(account.effectiveDisplayName(obfuscated: !showFullEmail))
                    .font(.subheadline.weight(.semibold))
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
            content()
        }
        .cardStyle()
    }

    private func limitRow(label: String, utilization: Double, kind: LimitBarKind, reset: String?) -> some View {
        let color = menuBarConfig.limitBarColor(for: kind, utilization: utilization, context: .dashboard)
        return VStack(alignment: .leading, spacing: 2) {
            LimitBar(label: label, utilization: utilization, color: color)
            if let reset {
                Text("Resets in \(reset)")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
                    .padding(.leading, 24)
            }
        }
    }

    @ViewBuilder
    private func staleHint(_ sampledAt: Date?) -> some View {
        if let sampledAt, Date().timeIntervalSince(sampledAt) >= 90 {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("Updated \(Text(sampledAt, style: .relative)) ago")
                    .font(.caption2)
            }
            .foregroundStyle(.textSecondary)
        }
    }

    @ViewBuilder
    private func statusLine(_ error: AppState.UsageErrorState?, expiredText: String? = nil) -> some View {
        if let error {
            HStack(spacing: 6) {
                Image(systemName: error.isRateLimited ? "timer" : (error.isExpired ? "exclamationmark.triangle" : "xmark.circle"))
                    .font(.caption)
                    .foregroundStyle(error.isExpired ? .yellow : .red)
                Text(error.isExpired ? (expiredText ?? String(localized: "Session expired — re-login", bundle: L10n.bundle)) : error.message)
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(2)
                Spacer()
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Waiting for usage data...")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
                Spacer()
            }
        }
    }
}

extension AppState {
    /// What a provider card shows: the real live account when there is one,
    /// else the first in-scope account, flagged as not live.
    struct CardAccount {
        let account: Account
        let isLive: Bool
        let isInScope: Bool
    }

    func cardAccount(for provider: AIProviderType) -> CardAccount? {
        let scoped = profileAccounts(for: provider)
        if let live = activeAccount(for: provider) {
            return CardAccount(account: live, isLive: true, isInScope: scoped.contains { $0.id == live.id })
        }
        guard let first = scoped.first else { return nil }
        return CardAccount(account: first, isLive: false, isInScope: true)
    }

    /// True while a profile switch or login owns the live credentials.
    /// (`isSwitching` is not @Published, so views cannot observe it.)
    var isAccountActionBusy: Bool {
        isSwitchingProfile || isLoggingIn || isLoggingInCodex
    }
}
