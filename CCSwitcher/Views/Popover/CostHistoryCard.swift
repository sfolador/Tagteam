import SwiftUI
import Charts

/// Last 14 days of API-equivalent cost as a bar chart with a hover callout.
struct CostHistoryCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var hovered: DailyCost?

    private static let windowDays = 14

    private var windowStart: Date {
        Calendar.current.date(byAdding: .day, value: -(Self.windowDays - 1), to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var days: [(day: DailyCost, date: Date)] {
        appState.costSummary.dailyCosts.compactMap { day in
            guard let date = day.parsedDate, date >= windowStart else { return nil }
            return (day, date)
        }
        .sorted { $0.date < $1.date }
    }

    private var todayString: String { TodayCostCard.dayFormatter.string(from: Date()) }

    var body: some View {
        let entries = days
        let total = entries.reduce(0) { $0 + $1.day.totalCost }

        GroupCard("Last 14 days", systemImage: "chart.bar", accessory: {
            if let hovered {
                Text(callout(hovered))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            } else if !entries.isEmpty {
                Text("Total \(TodayCostCard.formatCost(total))")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.textSecondary)
            }
        }) {
            if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "chart.bar")
                        .foregroundStyle(.textSecondary)
                    Text("No cost data yet")
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
                .redacted(reason: appState.isLoading ? .placeholder : [])
            } else {
                chart(entries)
            }
        }
    }

    private func chart(_ entries: [(day: DailyCost, date: Date)]) -> some View {
        let end = Calendar.current.startOfDay(for: Date())
        let middle = Calendar.current.date(byAdding: .day, value: -(Self.windowDays / 2), to: end) ?? end
        return Chart(entries, id: \.day.id) { entry in
            BarMark(
                x: .value("Day", entry.date, unit: .day),
                y: .value("Cost", entry.day.totalCost)
            )
            .foregroundStyle(entry.day.date == todayString ? Color.brand : Color.blue.opacity(0.6))
            .cornerRadius(2)
        }
        .chartXScale(domain: windowStart...end.addingTimeInterval(86_400))
        .chartXAxis {
            AxisMarks(values: [windowStart, middle, end]) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            let originX = geo[plot].origin.x
                            guard let date: Date = proxy.value(atX: location.x - originX) else { return }
                            hovered = entries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }?.day
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: 90)
    }

    private func callout(_ day: DailyCost) -> String {
        let models = day.modelBreakdown.sorted { $0.value > $1.value }
            .map { "\($0.key) \(TodayCostCard.formatCost($0.value))" }.joined(separator: ", ")
        let date = day.parsedDate?.formatted(.dateTime.month(.abbreviated).day()) ?? day.date
        let parts = [date, TodayCostCard.formatCost(day.totalCost), models].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
