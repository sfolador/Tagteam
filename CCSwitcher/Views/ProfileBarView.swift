import SwiftUI

/// Profile pills at the top of the popover: "All" + one pill per profile.
struct ProfileBarView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("settingsSection") private var settingsSection = ""

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill(
                        title: String(localized: "All", bundle: L10n.bundle),
                        symbol: "square.grid.2x2",
                        tint: .brand,
                        selected: appState.activeProfileId == nil
                    ) {
                        activate(nil)
                    }

                    ForEach(appState.profiles) { profile in
                        pill(
                            title: profile.name,
                            symbol: profile.symbol,
                            tint: profile.colorHex.flatMap(Color.init(hexRGB:)) ?? .brand,
                            selected: appState.activeProfileId == profile.id
                        ) {
                            activate(profile)
                        }
                    }

                    if appState.profiles.isEmpty {
                        Button(action: openProfileSettings) {
                            Label("New profile", systemImage: "plus")
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if appState.isSwitchingProfile {
                ProgressView()
                    .controlSize(.small)
            } else if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if !appState.profiles.isEmpty {
                Button(action: openProfileSettings) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().strokeBorder(.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("New profile")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func pill(title: String, symbol: String, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(selected ? tint : Color.clear)
                    .overlay(Capsule().strokeBorder(selected ? tint : Color.cardBorder, lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(appState.isAccountActionBusy)
    }

    private func activate(_ profile: Profile?) {
        guard appState.activeProfileId != profile?.id else { return }
        Task { await appState.activateProfile(profile) }
    }

    private func openProfileSettings() {
        settingsSection = "profiles"
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .ccswitcherOpenSettings, object: nil)
    }
}
