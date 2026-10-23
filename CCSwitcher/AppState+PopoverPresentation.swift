import Foundation

extension AppState {
    /// What a provider group shows as its live block: the real live account when
    /// there is one, else the first in-scope account, flagged as not live.
    struct PopoverAccount {
        let account: Account
        let isLive: Bool
        let isInScope: Bool
    }

    func popoverAccount(for provider: AIProviderType) -> PopoverAccount? {
        let scoped = profileAccounts(for: provider)
        if let live = activeAccount(for: provider) {
            return PopoverAccount(account: live, isLive: true, isInScope: scoped.contains { $0.id == live.id })
        }
        guard let first = scoped.first else { return nil }
        return PopoverAccount(account: first, isLive: false, isInScope: true)
    }

    /// True while a switch, profile switch or login owns the live credentials.
    /// Includes `isSwitching`, so automatic switches disable the UI too.
    var isCredentialActionBusy: Bool {
        isSwitching || isSwitchingProfile || isLoggingIn || isLoggingInCodex
    }
}
