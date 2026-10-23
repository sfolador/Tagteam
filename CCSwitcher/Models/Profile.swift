import Foundation

/// A named group of accounts across providers (e.g. "Personal", "Work").
///
/// Activating a profile makes one account per provider live — the profile's
/// last-used account for that provider, falling back to its first — and
/// restricts the popover's account list and auto-switch to the profile's
/// accounts. An account may belong to several profiles.
struct Profile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// SF Symbol name shown on the profile pill.
    var symbol: String
    /// Optional accent color as "#RRGGBB"; nil uses the app accent.
    var colorHex: String?
    /// Member accounts in display order. May mix Claude and Codex accounts.
    var accountIds: [UUID]
    /// Last account made active per provider while this profile was active,
    /// keyed by `AIProviderType.rawValue` (enum-keyed dictionaries don't
    /// encode as JSON objects).
    var lastActiveAccountIds: [String: UUID]

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "person.crop.circle",
        colorHex: String? = nil,
        accountIds: [UUID] = [],
        lastActiveAccountIds: [String: UUID] = [:]
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.accountIds = accountIds
        self.lastActiveAccountIds = lastActiveAccountIds
    }

    func contains(_ accountId: UUID) -> Bool {
        accountIds.contains(accountId)
    }

    func lastActiveAccountId(for provider: AIProviderType) -> UUID? {
        lastActiveAccountIds[provider.rawValue]
    }

    /// Which account of `provider` should be live once this profile is active:
    /// the live one if it is a member (no needless switch), else the member
    /// last made active under this profile, else the first member.
    /// Pure so it can be unit-tested; nil when the profile has no member of
    /// that provider.
    func activationTarget(for provider: AIProviderType, in accounts: [Account], liveId: UUID?) -> Account? {
        let members = accountIds.compactMap { id in
            accounts.first { $0.id == id && $0.provider == provider }
        }
        if let liveId, let live = members.first(where: { $0.id == liveId }) {
            return live
        }
        if let lastId = lastActiveAccountId(for: provider),
           let last = members.first(where: { $0.id == lastId }) {
            return last
        }
        return members.first
    }
}
