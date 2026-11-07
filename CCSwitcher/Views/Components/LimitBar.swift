import SwiftUI

/// Thin limit bar with a trailing tabular percentage, shared by the popover cards.
///
/// Unknown is not zero: a nil `utilization` draws a neutral track and "—".
struct LimitBar: View {
    enum Style {
        /// Label, bar, percentage and optional reset text on one line.
        case regular
        /// No label, fixed `AppStyle.compactBarWidth`, for account rows.
        case compact
    }

    let label: String
    let utilization: Double?
    let color: Color
    var style: Style = .regular
    /// Trailing reset text, e.g. "32 min" (regular style only).
    var reset: String? = nil
    /// Widened by callers that mix "5h"/"7d" with model names like "Fable",
    /// so every bar in the group still starts at the same x.
    var labelWidth: CGFloat = 22

    private var known: Double? {
        guard let utilization, utilization.isFinite else { return nil }
        return max(utilization, 0)
    }
    private var fraction: Double { known.map { min($0 / 100.0, 1.0) } ?? 0 }
    private var percentText: String { known.map { "\(Int($0))%" } ?? "—" }
    private var valueColor: Color { known == nil ? .textSecondary : color }

    var body: some View {
        if style == .compact {
            compactBody
        } else {
            regularBody
        }
    }

    private var compactBody: some View {
        HStack(spacing: 4) {
            track(height: 4)
                .frame(width: AppStyle.compactBarWidth, height: 4)
            Text(percentText)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(valueColor)
                .frame(minWidth: 30, alignment: .trailing)
        }
    }

    private var regularBody: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

            track(height: 6)
                .frame(height: 6)

            // Percentage and reset on one line, right-aligned in a fixed slot
            // so the bars of stacked rows end at the same x.
            HStack(spacing: 6) {
                Text(percentText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(valueColor)
                if let reset, !reset.isEmpty {
                    Text(reset)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
    }

    private func track(height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.progressTrack)
                if known != nil {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geo.size.width * fraction))
                        .opacity(fraction > 0 ? 1 : 0)
                }
            }
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

extension CodexUsage.Window {
    /// Label from the real window length: ≤ 6h "5h", ≥ 7d "7d", otherwise "Nh".
    /// Without a length, falls back to the slot's usual label.
    func limitLabel(fallback: String) -> String {
        guard let minutes = windowMinutes else { return fallback }
        if minutes <= 360 { return "5h" }
        if minutes >= 10080 { return "7d" }
        return "\(max(1, Int((Double(minutes) / 60).rounded())))h"
    }

    func limitKind(fallback: LimitBarKind) -> LimitBarKind {
        guard let minutes = windowMinutes else { return fallback }
        return minutes >= 10080 ? .weekly : .session
    }
}
