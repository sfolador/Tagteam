import SwiftUI

/// One non-card account: name, plan, compact short-window bar and an always-visible Switch.
/// Never a whole-row click target: a Codex switch restarts the desktop app.
struct AccountRowView: View {
    let account: Account

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var menuBarConfig: MenuBarConfig
    @AppStorage("showFullEmail") private var showFullEmail = false
    @StateObject private var actions = AccountActionsModel()
    @State private var isSwitchingThis = false

    /// A usage window read from whichever provider this account belongs to.
    private struct Reading {
        let label: String
        let kind: LimitBarKind
        let utilization: Double?
        let resetText: String?
    }

    private var fiveHour: Reading? {
        if account.provider == .codex {
            return appState.codexUsage[account.id]?.primary.map { reading($0, fallback: "5h", kind: .session) }
        }
        return appState.accountUsage[account.id]?.fiveHour.map {
            Reading(label: "5h", kind: .session, utilization: $0.utilization, resetText: $0.resetsAtDate.map(resetCountdownString(until:)))
        }
    }

    private var sevenDay: Reading? {
        if account.provider == .codex {
            return appState.codexUsage[account.id]?.secondary.map { reading($0, fallback: "7d", kind: .weekly) }
        }
        return appState.accountUsage[account.id]?.sevenDay.map {
            Reading(label: "7d", kind: .weekly, utilization: $0.utilization, resetText: $0.resetsAtDate.map(resetCountdownString(until:)))
        }
    }

    private func reading(_ w: CodexUsage.Window, fallback: String, kind: LimitBarKind) -> Reading {
        Reading(
            label: w.limitLabel(fallback: fallback),
            kind: w.limitKind(fallback: kind),
            utilization: w.usedPercent,
            resetText: w.resetsAt.map(resetCountdownString(until:))
        )
    }

    private var usageError: AppState.UsageErrorState? {
        account.provider == .codex ? appState.codexUsageErrors[account.id] : appState.accountUsageErrors[account.id]
    }

    private var sampledAt: Date? {
        account.provider == .codex ? appState.codexUsageSampledAt[account.id] : appState.accountUsageSampledAt[account.id]
    }

    private var hasExtraUsage: Bool {
        account.provider == .claudeCode && appState.accountUsage[account.id]?.extraUsage?.isEnabled == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    nameBlock
                    HStack(spacing: 6) {
                        usageBlock
                        if hasExtraUsage {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                switchButton
                AccountActionsMenu(account: account, model: actions)
            }
            staleHint
        }
        .padding(.vertical, AppStyle.rowVerticalPadding)
        .accountActions(account: account, model: actions)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var nameBlock: some View {
        if actions.isEditingLabel {
            AccountLabelEditor(account: account, model: actions)
        } else {
            HStack(spacing: 6) {
                Text(account.effectiveDisplayName(obfuscated: !showFullEmail))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(2)
                if let sub = account.displaySubscriptionType {
                    Text(sub)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.brand)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.brand.opacity(0.15), in: Capsule())
                        .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var usageBlock: some View {
        if let short = fiveHour {
            HoverTip(tipText) {
                shortBar(short)
            }
        } else if let error = usageError {
            HoverTip(errorText(error)) {
                Image(systemName: error.isRateLimited ? "timer" : (error.isExpired ? "exclamationmark.triangle" : "xmark.circle"))
                    .font(.caption)
                    .foregroundStyle(error.isExpired ? .yellow : .red)
            }
        } else if sevenDay != nil {
            // Weekly reading without a short one: keep the value reachable.
            HoverTip(tipText) {
                LimitBar(label: "", utilization: nil, color: .clear, style: .compact)
            }
        } else {
            LimitBar(label: "", utilization: nil, color: .clear, style: .compact)
        }
    }

    private func shortBar(_ short: Reading) -> some View {
        LimitBar(
            label: "",
            utilization: short.utilization,
            color: short.utilization.map { menuBarConfig.limitBarColor(for: short.kind, utilization: $0, context: .dashboard) } ?? .clear,
            style: .compact
        )
    }

    private func errorText(_ error: AppState.UsageErrorState) -> String {
        guard error.isExpired else { return error.message }
        return account.provider == .codex
            ? String(localized: "Waiting for the Codex CLI to refresh its session", bundle: L10n.bundle)
            : String(localized: "Session expired — re-login", bundle: L10n.bundle)
    }

    /// Email, then each window's value and reset; an omitted window gets no line.
    private var tipText: String {
        var lines = [account.displayEmail(obfuscated: !showFullEmail)]
        if let short = fiveHour, let reset = short.resetText {
            lines.append(String(localized: "\(short.label) resets in \(reset)", bundle: L10n.bundle))
        }
        if let weekly = sevenDay {
            let value = weekly.utilization.map { "\(Int($0))%" } ?? "—"
            if let reset = weekly.resetText {
                lines.append(String(localized: "\(weekly.label): \(value) · resets \(reset)", bundle: L10n.bundle))
            } else {
                lines.append(String(localized: "\(weekly.label): \(value)", bundle: L10n.bundle))
            }
        }
        return lines.joined(separator: "\n")
    }

    private var switchButton: some View {
        Button {
            isSwitchingThis = true
            Task {
                await appState.switchTo(account)
                isSwitchingThis = false
            }
        } label: {
            if isSwitchingThis {
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
    private var staleHint: some View {
        if let sampledAt, Date().timeIntervalSince(sampledAt) >= 90 {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text("Updated \(Text(sampledAt, style: .relative)) ago")
            }
            .font(.caption)
            .foregroundStyle(.textSecondary)
            .padding(.leading, 15)
        }
    }
}
