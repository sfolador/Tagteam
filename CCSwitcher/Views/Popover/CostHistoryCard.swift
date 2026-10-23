import SwiftUI

/// Last 14 days of API-equivalent cost as a compact vertical list (newest first):
/// short date, a bar proportional to cost, and the amount.
struct CostHistoryCard: View {
    @EnvironmentObject private var appState: AppState

    private static let windowDays = 14

    private var windowStart: Date {
        Calendar.current.date(byAdding: .day, value: -(Self.windowDays - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var days: [(day: DailyCost, date: Date)] {
        appState.costSummary.dailyCosts.compactMap { day in
            guard let date = day.parsedDate, date >= windowStart else { return nil }
            return (day, date)
        }
        .sorted { $0.date > $1.date }
    }

    private var todayString: String { TodayCostCard.dayFormatter.string(from: Date()) }

    var body: some View {
        let entries = days
        let total = entries.reduce(0) { $0 + $1.day.totalCost }
        let maxCost = max(0.0001, entries.map { $0.day.totalCost }.max() ?? 0)

        GroupCard("Last 14 days", systemImage: "chart.bar", accessory: {
            if !entries.isEmpty {
                Text("Total \(TodayCostCard.formatCost(total))")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.textSecondary)
            }
        }) {
            if entries.isEmpty {
                Text("No cost data yet")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .redacted(reason: appState.isLoading ? .placeholder : [])
            } else {
                VStack(spacing: 2) {
                    ForEach(entries, id: \.day.id) { entry in
                        row(entry.day, date: entry.date, maxCost: maxCost)
                    }
                }
            }
        }
    }

    private func row(_ day: DailyCost, date: Date, maxCost: Double) -> some View {
        let isToday = day.date == todayString
        return HStack(spacing: 6) {
            Text(date.formatted(.dateTime.day().month(.defaultDigits)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.textSecondary)
                .frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isToday ? Color.brand : Color.blue.opacity(0.6))
                    .frame(width: max(2, geo.size.width * CGFloat(day.totalCost / maxCost)))
                    .frame(maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 8)
            Text(Self.shortCost(day.totalCost))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(isToday ? Color.primary : Color.textSecondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(height: 15)
        .help(callout(day))
    }

    private static func shortCost(_ cost: Double) -> String {
        cost >= 1 ? String(format: "$%.2f", cost) : String(format: "$%.3f", cost)
    }

    private func callout(_ day: DailyCost) -> String {
        let models = day.modelBreakdown.sorted { $0.value > $1.value }
            .map { "\($0.key) \(TodayCostCard.formatCost($0.value))" }.joined(separator: ", ")
        let date = day.parsedDate?.formatted(.dateTime.month(.abbreviated).day()) ?? day.date
        let parts = [date, TodayCostCard.formatCost(day.totalCost), models].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
