import SwiftUI

/// Settings tab for creating profiles and choosing which accounts belong to each.
struct ProfilesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("showFullEmail") private var showFullEmail = false
    @State private var selectedId: UUID?
    @State private var pendingDelete: Profile?

    private static let symbols = [
        "person.fill", "briefcase.fill", "house.fill", "building.2.fill",
        "graduationcap.fill", "hammer.fill", "flask.fill", "star.fill",
        "heart.fill", "leaf.fill", "gamecontroller.fill", "sparkles",
    ]

    private static let palette: [String] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#00C7BE", "#007AFF", "#AF52DE", "#FF2D55",
    ]

    var body: some View {
        Group {
            if appState.profiles.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 170)
                    Divider()
                    detail
                }
            }
        }
        .onAppear { ensureSelection() }
        .onChange(of: appState.profiles) { _, _ in ensureSelection() }
        .confirmationDialog(
            "Delete profile?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { profile in
            Button("Delete \(profile.name)", role: .destructive) {
                appState.deleteProfile(profile)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("The accounts themselves are kept; only the grouping is removed.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No profiles yet")
                .font(.title3.weight(.semibold))
            Text("A profile groups Claude Code and Codex accounts, for example Personal and Work. Activating a profile makes one account per provider live and limits the popover and auto-switch to that profile's accounts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                Button("Create Personal and Work") {
                    let personal = appState.createProfile(name: String(localized: "Personal", bundle: L10n.bundle), symbol: "person.fill", colorHex: Self.palette[5])
                    appState.createProfile(name: String(localized: "Work", bundle: L10n.bundle), symbol: "briefcase.fill", colorHex: Self.palette[1])
                    selectedId = personal.id
                }
                .buttonStyle(.borderedProminent)
                Button("New profile") { addProfile() }
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedId) {
                ForEach(appState.profiles) { profile in
                    HStack(spacing: 8) {
                        Image(systemName: profile.symbol)
                            .foregroundStyle(color(for: profile))
                            .frame(width: 18)
                        Text(profile.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if appState.activeProfileId == profile.id {
                            Circle().fill(.green).frame(width: 7, height: 7)
                        }
                    }
                    .tag(profile.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 4) {
                Button { addProfile() } label: { Image(systemName: "plus") }
                    .help("New profile")
                Button {
                    if let profile = selectedProfile { pendingDelete = profile }
                } label: { Image(systemName: "minus") }
                    .help("Delete profile")
                    .disabled(selectedProfile == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let profile = selectedProfile {
            ProfileDetail(
                profile: profile,
                symbols: Self.symbols,
                palette: Self.palette,
                showFullEmail: showFullEmail
            )
            .id(profile.id)
        } else {
            Text("Select a profile")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private var selectedProfile: Profile? {
        appState.profiles.first { $0.id == selectedId }
    }

    private func color(for profile: Profile) -> Color {
        profile.colorHex.flatMap { Color(hexRGB: $0) } ?? .accentColor
    }

    private func addProfile() {
        let created = appState.createProfile(
            name: String(localized: "Profile \(appState.profiles.count + 1)", bundle: L10n.bundle),
            symbol: "person.fill",
            colorHex: nil
        )
        selectedId = created.id
    }

    private func ensureSelection() {
        if selectedProfile == nil {
            selectedId = appState.activeProfileId.flatMap { id in
                appState.profiles.first { $0.id == id }?.id
            } ?? appState.profiles.first?.id
        }
    }
}

// MARK: - Detail

private struct ProfileDetail: View {
    @EnvironmentObject private var appState: AppState
    let profile: Profile
    let symbols: [String]
    let palette: [String]
    let showFullEmail: Bool

    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(profile: Profile, symbols: [String], palette: [String], showFullEmail: Bool) {
        self.profile = profile
        self.symbols = symbols
        self.palette = palette
        self.showFullEmail = showFullEmail
        _name = State(initialValue: profile.name)
    }

    private var isActive: Bool { appState.activeProfileId == profile.id }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }

                LabeledContent("Symbol") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 6), spacing: 4) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button { update { $0.symbol = symbol } } label: {
                                Image(systemName: symbol)
                                    .frame(width: 24, height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(profile.symbol == symbol ? Color.accentColor.opacity(0.25) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                LabeledContent("Color") {
                    HStack(spacing: 6) {
                        swatch(hex: nil)
                        ForEach(palette, id: \.self) { swatch(hex: $0) }
                    }
                }
            }

            Section {
                HStack {
                    if isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not active").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if appState.isSwitchingProfile {
                        ProgressView().controlSize(.small)
                    }
                    Button(isActive ? "Show all accounts" : "Activate") {
                        Task { await appState.activateProfile(isActive ? nil : profile) }
                    }
                    .disabled(appState.isSwitchingProfile)
                }
            } footer: {
                Text("Activating makes one account per provider live: the current one if it is a member, otherwise the last one used in this profile, otherwise the first member below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            memberSection(.claudeCode, title: "Claude Code")
            memberSection(.codex, title: "Codex")
        }
        .formStyle(.grouped)
    }

    private func memberSection(_ provider: AIProviderType, title: LocalizedStringKey) -> some View {
        let accounts = orderedAccounts(for: provider)
        return Section(title) {
            if accounts.isEmpty {
                Text("No accounts yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts) { account in
                Toggle(isOn: membership(for: account)) {
                    Text(account.effectiveDisplayName(obfuscated: !showFullEmail))
                    HStack(spacing: 4) {
                        Text(account.displayEmail(obfuscated: !showFullEmail))
                        if let plan = account.displaySubscriptionType {
                            Text("· \(plan)")
                        }
                    }
                }
            }
        }
    }

    /// Members first in profile order, then the remaining accounts in stored order.
    private func orderedAccounts(for provider: AIProviderType) -> [Account] {
        let all = appState.accounts(for: provider)
        let members = profile.accountIds.compactMap { id in all.first { $0.id == id } }
        let memberIds = Set(members.map(\.id))
        return members + all.filter { !memberIds.contains($0.id) }
    }

    private func membership(for account: Account) -> Binding<Bool> {
        Binding(
            get: { profile.contains(account.id) },
            set: { appState.setAccount(account, in: profile, included: $0) }
        )
    }

    private func swatch(hex: String?) -> some View {
        let fill = hex.flatMap { Color(hexRGB: $0) } ?? Color.accentColor
        let selected = profile.colorHex == hex
        return Button { update { $0.colorHex = hex } } label: {
            Circle()
                .fill(fill)
                .frame(width: 16, height: 16)
                .overlay {
                    if hex == nil {
                        Image(systemName: "slash.circle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(Circle().strokeBorder(.primary.opacity(selected ? 0.8 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .help(hex.map { LocalizedStringKey($0) } ?? LocalizedStringKey("Default"))
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = profile.name
            return
        }
        if trimmed != profile.name { update { $0.name = trimmed } }
    }

    private func update(_ change: (inout Profile) -> Void) {
        var copy = appState.profiles.first { $0.id == profile.id } ?? profile
        change(&copy)
        appState.updateProfile(copy)
    }
}
