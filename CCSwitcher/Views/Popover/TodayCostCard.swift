import SwiftUI

/// Today's API-equivalent cost plus 7 / 30 day totals. Local Claude Code logs only.
struct TodayCostCard: View {
    @EnvironmentObject private var appState: AppState

    private var summary: CostSummary { appState.costSummary }
    /// No log data yet: show "—", never a fake $0.
    private var hasData: Bool { !summary.dailyCosts.isEmpty }
    private var isLoadingFirstData: Bool { appState.isLoading && !hasData }

    var body: some View {
        GroupCard("Today", systemImage: "dollarsign.circle") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HoverTip {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Estimated API-equivalent cost of your Claude Code usage, for reference only.")
                            Text("Cost is computed from your local Claude Code session logs (jsonl files) under ~/.claude/projects/.")
                                .foregroundStyle(.textSecondary)
                            if let v = VerifiedAgainst.load() {
                                Text("Verified against ccusage \(v.ccusageVersion) on \(v.verifiedOn) — \(v.windowDays)-day total matched to the cent.")
                                    .foregroundStyle(.textSecondary)
                            }
                        }
                    } content: {
                        HStack(spacing: 4) {
                            Text(hasData ? Self.formatCost(summary.todayCost) : "—")
                                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(hasData ? Color.green : Color.textSecondary)
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    Text("API-equivalent")
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                    Text("Claude Code · This Mac")
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    periodRow("7 days", days: 7)
                    periodRow("30 days", days: 30)
                }
            }
            .redacted(reason: isLoadingFirstData ? .placeholder : [])
        }
    }

    private func periodRow(_ label: LocalizedStringKey, days: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.textSecondary)
            Text(hasData ? Self.formatCost(costForLastDays(days)) : "—")
                .font(.callout.weight(.medium).monospacedDigit())
        }
    }

    private func costForLastDays(_ days: Int) -> Double {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date())) else { return 0 }
        let startStr = Self.dayFormatter.string(from: start)
        let todayStr = Self.dayFormatter.string(from: Date())
        return summary.dailyCosts
            .filter { $0.date >= startStr && $0.date <= todayStr }
            .reduce(0) { $0 + $1.totalCost }
    }

    static func formatCost(_ cost: Double) -> String {
        cost >= 1 ? String(format: "$%.2f", cost) : String(format: "$%.4f", cost)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
