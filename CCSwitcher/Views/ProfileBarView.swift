import SwiftUI

/// Popover header: "All" + one pill per profile, "+", then "Updated …" and ↻.
struct ProfileBarView: View {
    @EnvironmentObject private var appState: AppState

    private let pillHeight: CGFloat = 26
    private let pillRadius: CGFloat = 8

    private var isRefreshing: Bool { appState.isLoading || appState.isSwitchingProfile }

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill(
                        title: String(localized: "All", bundle: L10n.bundle),
                        symbol: "square.grid.2x2",
                        tint: .brand,
                        selected: appState.activeProfileId == nil,
                        shortcutIndex: 0
                    ) {
                        activate(nil)
                    }

                    ForEach(Array(appState.profiles.enumerated()), id: \.element.id) { index, profile in
                        pill(
                            title: profile.name,
                            symbol: profile.symbol,
                            tint: profile.colorHex.flatMap(Color.init(hexRGB:)) ?? .brand,
                            selected: appState.activeProfileId == profile.id,
                            shortcutIndex: index + 1
                        ) {
                            activate(profile)
                        }
                    }

                    Button { SettingsDeepLink.open("profiles") } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.textSecondary)
                            .frame(width: pillHeight, height: pillHeight)
                            .background(
                                RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                                    .strokeBorder(.cardBorder, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("New profile")
                }
                .padding(.vertical, 1)
            }

            updatedLabel

            Button {
                Task { await appState.refresh() }
            } label: {
                ZStack {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.textSecondary)
                    }
                }
                .frame(width: pillHeight, height: pillHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isRefreshing)
            .help("Refresh")
        }
    }

    private var updatedLabel: some View {
        Group {
            if isRefreshing {
                Text("Refreshing…")
            } else if let last = appState.lastUsageRefresh {
                // Re-evaluated every 30 s so "2 min. ago" does not go stale while the popover stays open.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(updatedText(since: last, now: context.date))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.textSecondary)
        .lineLimit(1)
        .fixedSize()
    }

    private func updatedText(since date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: min(date, now), relativeTo: now)
        return String(localized: "Updated \(relative)", bundle: L10n.bundle)
    }

    private func pill(
        title: String,
        symbol: String,
        tint: Color,
        selected: Bool,
        shortcutIndex: Int,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Self.contentColor(on: tint) : Color.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: pillHeight)
            .background(shape.fill(selected ? tint : Color.cardFill))
            .overlay(shape.strokeBorder(selected ? tint : Color.cardBorder, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(appState.isCredentialActionBusy)
        .modifier(PillShortcut(index: shortcutIndex))
    }

    /// Black or white text, whichever contrasts more with the pill tint.
    private static func contentColor(on tint: Color) -> Color {
        guard let rgb = NSColor(tint).usingColorSpace(.sRGB) else { return .white }
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
        // Contrast against white vs black; pick the larger ratio.
        return (1.05 / (luminance + 0.05)) >= ((luminance + 0.05) / 0.05) ? .white : .black
    }

    private func activate(_ profile: Profile?) {
        guard appState.activeProfileId != profile?.id else { return }
        Task { await appState.activateProfile(profile) }
    }
}

/// ⌘0 for "All", ⌘1…⌘9 for the profiles; further profiles have no shortcut.
private struct PillShortcut: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index <= 9 {
            content.keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
        } else {
            content
        }
    }
}
