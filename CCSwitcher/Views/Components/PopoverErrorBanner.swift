import SwiftUI

/// Full-width error strip above the popover footer: two-line preview, a
/// "Details…" popover with the full selectable text, and a × that dismisses it.
struct PopoverErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    @State private var showDetails = false
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Details…") { showDetails = true }
                .buttonStyle(.link)
                .font(.caption)
                .focusable(false)
                .popover(isPresented: $showDetails, arrowEdge: .top) {
                    ScrollView {
                        Text(message)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(width: 360)
                    .frame(maxHeight: 240)
                    .environment(\.locale, locale)
                }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.textSecondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }
}
