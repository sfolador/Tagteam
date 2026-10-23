import SwiftUI

/// Today's Claude Code activity (turns, active time, lines) and model mix.
struct ActivityCard: View {
    @EnvironmentObject private var appState: AppState

    private var stats: ActivityStats { appState.activityStats }

    /// Models actually seen today, most used first. Zero-count rows are hidden.
    private var models: [(name: String, count: Int)] {
        stats.topModels.filter { $0.count > 0 }
    }

    private var isEmpty: Bool {
        stats.conversationTurns == 0 && stats.activeCodingMinutes == 0
            && stats.linesWritten == 0 && models.isEmpty
    }

    var body: some View {
        GroupCard("Activity", systemImage: "waveform.path.ecg", accessory: {
            Text("Claude Code · This Mac")
                .font(.caption)
                .foregroundStyle(.textSecondary)
        }) {
            if isEmpty {
                Text("No Claude Code activity yet today")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                HStack(spacing: 0) {
                    stat(icon: "bubble.left.and.bubble.right", value: "\(stats.conversationTurns)", label: "Turns",
                         tooltip: "Messages you sent to Claude Code today")
                    stat(icon: "clock", value: stats.activeCodingTimeString, label: "Active",
                         tooltip: "Estimated total time Claude worked for you today. Parallel sessions stack. Idle gaps >10 min excluded. This is an approximation based on message timestamps, not exact.")
                    stat(icon: "doc.text", value: "\(stats.linesWritten)", label: "Lines",
                         tooltip: "Estimated lines of code written by Claude via Edit/Write tools")
                }

                if !models.isEmpty {
                    GroupDivider()
                    modelMix
                }
            }
        }
    }

    private func stat(icon: String, value: String, label: LocalizedStringKey, tooltip: LocalizedStringKey) -> some View {
        HoverTip {
            Text(tooltip)
        } content: {
            VStack(spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                HStack(spacing: 4) {
                    Image(systemName: icon)
                    Text(label)
                }
                .font(.caption)
                .foregroundStyle(.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Model mix

    private var modelMix: some View {
        let total = max(1, models.reduce(0) { $0 + $1.count })
        return VStack(alignment: .leading, spacing: 8) {
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
            .frame(height: 8)

            // Wraps to as many lines as needed at 350 pt.
            FlowLayout(spacing: 10) {
                ForEach(models, id: \.name) { model in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Self.modelColor(model.name))
                            .frame(width: 7, height: 7)
                        Text("\(model.name) \(model.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
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
}

/// Minimal wrapping row layout for the model legend.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
