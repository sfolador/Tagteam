import SwiftUI

/// Rounded grouped card: an uppercase title row with an optional trailing
/// accessory, then rows separated by `GroupDivider`.
struct GroupCard<Accessory: View, Content: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let accessory: Accessory
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                accessory
            }
            .frame(minHeight: 18)
            content
        }
        .padding(AppStyle.groupPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.groupCornerRadius, style: .continuous)
                .fill(.cardFillStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.groupCornerRadius, style: .continuous)
                .strokeBorder(.cardBorder, lineWidth: 1)
        )
    }
}

/// Hairline divider for rows inside a `GroupCard`.
struct GroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(.cardBorder)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
