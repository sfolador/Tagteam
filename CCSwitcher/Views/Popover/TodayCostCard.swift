import SwiftUI

/// Compact, secondary "Costs" card: today / 7 / 30 day API-equivalent cost and a
/// slim model-mix bar. Local Claude Code logs only.
struct TodayCostCard: View {
    @EnvironmentObject private var appState: AppState

    private var summary: CostSummary { appState.costSummary }
    /// No log data yet: show "—", never a fake $0.
    private var hasData: Bool { !summary.dailyCosts.isEmpty }
    private var isLoadingFirstData: Bool { appState.isLoading && !hasData }

    /// Models actually seen today, most used first. Zero-count rows are hidden.
    private var models: [(name: String, count: Int)] {
        appState.activityStats.topModels.filter { $0.count > 0 }
    }

    var body: some View {
        // Plain Text values computed up front: the tip must not depend on the environment.
        let tip = infoTip()
        GroupCard("Costs", systemImage: "dollarsign.circle", accessory: {
            HoverTip {
                tip
            } content: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    figure("Today", value: hasData ? Self.formatCost(summary.todayCost) : "—")
                    figure("7 days", value: hasData ? Self.formatCost(costForLastDays(7)) : "—")
                    figure("30 days", value: hasData ? Self.formatCost(costForLastDays(30)) : "—")
                }
                .redacted(reason: isLoadingFirstData ? .placeholder : [])

                if !models.isEmpty {
                    modelMix
                }

                Text("Claude Code · This Mac · API-equivalent")
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func figure(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.textSecondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoTip() -> Text {
        var tip = Text("Estimated API-equivalent cost of your Claude Code usage, for reference only.")
            + Text("\n\n")
            + Text("Cost is computed from your local Claude Code session logs (jsonl files) under ~/.claude/projects/.")
        if let v = VerifiedAgainst.load() {
            tip = tip + Text("\n\n")
                + Text("Verified against ccusage \(v.ccusageVersion) on \(v.verifiedOn) — \(v.windowDays)-day total matched to the cent.")
        }
        return tip
    }

    // MARK: - Model mix

    private var modelMix: some View {
        let total = max(1, models.reduce(0) { $0 + $1.count })
        let summaryText = models.map { "\($0.name) \($0.count)" }.joined(separator: " · ")
        return HoverTip(summaryText) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(models, id: \.name) { model in
                        Rectangle()
                            .fill(Self.modelColor(model.name))
                            .frame(width: max(2, geo.size.width * CGFloat(model.count) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)
        }
    }

    static func modelColor(_ name: String) -> Color {
        switch name {
        case "Fable": return .purple
        case "Opus": return .brand
        case "Sonnet": return .blue
        case "Haiku": return .green
        default: return .gray
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
