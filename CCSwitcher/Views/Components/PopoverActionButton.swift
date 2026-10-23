import SwiftUI

/// Full-width footer button styled as a card (reference: Settings | Quit).
struct PopoverActionButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let action: () -> Void
    @State private var isHovering = false

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.textPrimary)
                .frame(maxWidth: .infinity, minHeight: AppStyle.footerButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.groupCornerRadius, style: .continuous)
                .fill(.cardFillStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyle.groupCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.groupCornerRadius, style: .continuous)
                .strokeBorder(.cardBorder, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }
}
