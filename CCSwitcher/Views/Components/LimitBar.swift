import SwiftUI

/// Thin limit bar with a trailing tabular percentage, shared by the provider cards.
struct LimitBar: View {
    let label: String
    let utilization: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.textSecondary)
                .frame(width: 18, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                        .fill(.progressTrack)
                    RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * min(utilization / 100.0, 1.0)))
                }
            }
            .frame(height: 5)

            Text("\(Int(utilization))%")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

/// "2 hr 5 min" style countdown, matching `UsageWindow.resetTimeString` but localized.
func resetCountdownString(until date: Date) -> String {
    let remaining = date.timeIntervalSinceNow
    guard remaining > 0 else { return String(localized: "now", bundle: L10n.bundle) }
    let hours = Int(remaining) / 3600
    let minutes = (Int(remaining) % 3600) / 60
    if hours > 24 {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
        return formatter.string(from: date)
    } else if hours > 0 {
        return String(localized: "\(hours) hr \(minutes) min", bundle: L10n.bundle)
    }
    return String(localized: "\(minutes) min", bundle: L10n.bundle)
}
