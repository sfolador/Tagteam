import Foundation

private let log = FileLog("AppState+Profiles")

/// Profiles and Codex public API used by the views.
///
/// Existing `switchTo(_:)`, `removeAccount(_:)` and
/// `updateAccountLabel(_:label:)` handle accounts of either provider.
extension AppState {
    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileId }
    }

    /// Live account for `provider` (Claude: `activeAccount`, Codex: `activeCodexAccount`).
    func activeAccount(for provider: AIProviderType) -> Account? {
        switch provider {
        case .claudeCode: activeAccount
        case .codex: activeCodexAccount
        case .gemini: nil
        }
    }

    /// Every known account of `provider`, in stored order.
    func accounts(for provider: AIProviderType) -> [Account] {
        accounts.filter { $0.provider == provider }
    }

    /// Accounts of `provider` in the active profile, in profile order;
    /// all accounts of `provider` when no profile is active.
    func profileAccounts(for provider: AIProviderType) -> [Account] {
        guard let profile = activeProfile else { return accounts(for: provider) }
        return profile.accountIds.compactMap { id in
            accounts.first { $0.id == id && $0.provider == provider }
        }
    }

    func profiles(containing account: Account) -> [Profile] {
        profiles.filter { $0.contains(account.id) }
    }

    @discardableResult
    func createProfile(name: String, symbol: String, colorHex: String?) -> Profile {
        let profile = Profile(
            name: name.trimmingCharacters(in: .whitespaces),
            symbol: symbol,
            colorHex: colorHex
        )
        profiles.append(profile)
        saveProfiles()
        return profile
    }

    /// Persist edits to name, symbol, color or member order.
    func updateProfile(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        saveProfiles()
    }

    /// Deleting the active profile falls back to "All accounts" without switching.
    func deleteProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileId == profile.id {
            activeProfileId = nil
        }
        saveProfiles()
    }

    func setAccount(_ account: Account, in profile: Profile, included: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        if included {
            if !profiles[index].contains(account.id) {
                profiles[index].accountIds.append(account.id)
            }
        } else {
            profiles[index].accountIds.removeAll { $0 == account.id }
            profiles[index].lastActiveAccountIds = profiles[index].lastActiveAccountIds.filter { $0.value != account.id }
        }
        saveProfiles()
    }

    /// Make `profile` active (nil = "All accounts"). For each provider with
    /// members, keep the live account if it is a member, else switch to the
    /// profile's last-active member for that provider, else its first member.
    func activateProfile(_ profile: Profile?) async {
        guard !isSwitchingProfile, !isSwitching, !isLoggingIn, !isLoggingInCodex else {
            log.warning("[activateProfile] Skipped: a switch or login is in progress")
            return
        }
        // Resolve against the stored copy: the caller's value may be stale.
        let resolved = profile.flatMap { candidate in profiles.first { $0.id == candidate.id } }
        if profile != nil, resolved == nil { return }

        isSwitchingProfile = true
        defer { isSwitchingProfile = false }
        errorMessage = nil
        // Set before switching so the switches record "last active" under the
        // new profile and candidate lists already reflect it.
        activeProfileId = resolved?.id
        saveProfiles()

        var failures: [String] = []
        if let resolved {
            for provider in [AIProviderType.claudeCode, .codex] {
                guard let target = resolved.activationTarget(
                    for: provider, in: accounts, liveId: activeAccount(for: provider)?.id
                ) else { continue }

                if activeAccount(for: provider)?.id == target.id {
                    recordLastActive(target)
                    continue
                }
                let switched = await performSwitch(target, refreshAfter: false)
                if !switched || activeAccount(for: provider)?.id != target.id {
                    let reason = errorMessage ?? String(localized: "could not switch", bundle: L10n.bundle)
                    failures.append("\(provider.rawValue): \(reason)")
                    errorMessage = nil
                }
            }
        }

        isLoading = false
        // refresh() skips while a profile switch runs; this one is ours.
        isSwitchingProfile = false
        await refresh()
        // refresh() clears errorMessage, so surface partial failures afterwards.
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    /// Run `codex login` and add (or refresh) the resulting account; it joins
    /// the active profile, if any.
    func loginNewCodexAccount() async {
        guard !isSwitching, !isLoggingIn, !isLoggingInCodex else {
            log.warning("[loginNewCodexAccount] Skipped: a switch or another login is in progress")
            return
        }
        isLoggingInCodex = true
        errorMessage = nil

        // Codex rotates tokens in auth.json in place; login overwrites the file,
        // so bank the live account's current tokens first — but only when the
        // file really is that account's login.
        if let current = activeCodexAccount,
           case .success(.some(let identity)) = await codexResult(try await CodexService.shared.readCurrentIdentity()),
           current.providerAccountId == nil || current.providerAccountId == identity.providerKey {
            _ = await codexResult(try await CodexService.shared.captureCurrentCredentials(forAccountId: current.id))
        }

        switch await codexResult(try await CodexService.shared.login()) {
        case .failure(.loginCancelled):
            log.info("[loginNewCodexAccount] Cancelled")
            isLoggingInCodex = false
        case .failure(let error):
            errorMessage = error.localizedDescription
            log.error("[loginNewCodexAccount] \(error.localizedDescription)")
            isLoggingInCodex = false
        case .success(let identity):
            let adopted = await adoptCodexIdentity(identity)
            if !adopted {
                // login() already replaced auth.json; put the previous login back.
                switch await codexResult(try await CodexService.shared.discardPendingLogin()) {
                case .success: log.info("[loginNewCodexAccount] Adopt failed; previous login restored")
                case .failure(let error): log.error("[loginNewCodexAccount] discardPendingLogin failed: \(error.localizedDescription)")
                }
            }
            isLoggingInCodex = false
            if adopted {
                await refresh()
            }
        }
    }

    /// Adopt the login already present in ~/.codex/auth.json as an account.
    func importCurrentCodexLogin() async {
        guard !isSwitching, !isLoggingIn, !isLoggingInCodex else {
            log.warning("[importCurrentCodexLogin] Skipped: a switch or login is in progress")
            return
        }
        isLoggingInCodex = true
        errorMessage = nil

        switch await codexResult(try await CodexService.shared.readCurrentIdentity()) {
        case .failure(let error):
            errorMessage = error.localizedDescription
            isLoggingInCodex = false
        case .success(nil):
            errorMessage = CodexServiceError.notLoggedIn.localizedDescription
            isLoggingInCodex = false
        case .success(.some(let identity)):
            let adopted = await adoptCodexIdentity(identity)
            isLoggingInCodex = false
            if adopted {
                await refresh()
            }
        }
    }

    func cancelCodexLogin() {
        Task { await CodexService.shared.cancelLogin() }
    }

    // MARK: - Internal helpers

    /// Store the login currently in auth.json as a (new or existing) Codex
    /// account and make it live. De-duplicated by user+ChatGPT account id (providerKey), never
    /// by email — one person can hold several workspaces under one email.
    private func adoptCodexIdentity(_ identity: CodexIdentity) async -> Bool {
        guard !identity.isApiKey, identity.chatgptAccountId != nil else {
            errorMessage = String(localized: "This Codex login uses an API key, not a ChatGPT account, so it cannot be managed here.", bundle: L10n.bundle)
            return false
        }
        let providerId = identity.providerKey
        let email = identity.email ?? String(localized: "Codex account", bundle: L10n.bundle)
        let existing = accounts.firstIndex { $0.provider == .codex && $0.providerAccountId == providerId }
        // Defence in depth: the same provider key must never swap in a
        // different person's email.
        if let existing, let known = identity.email, accounts[existing].email != known {
            errorMessage = String(localized: "This Codex login does not match the stored account.", bundle: L10n.bundle)
            log.error("[adoptCodexIdentity] Refusing: email mismatch for existing account \(accounts[existing].id)")
            return false
        }
        let accountId = existing.map { accounts[$0].id } ?? UUID()

        if case .failure(let error) = await codexResult(try await CodexService.shared.captureCurrentCredentials(forAccountId: accountId)) {
            errorMessage = error.localizedDescription
            log.error("[adoptCodexIdentity] Capture failed: \(error.localizedDescription)")
            return false
        }

        let account: Account
        if let existing {
            accounts[existing].subscriptionType = identity.planType ?? accounts[existing].subscriptionType
            accounts[existing].providerAccountId = providerId
            account = accounts[existing]
            log.info("[adoptCodexIdentity] Existing account \(account.id); backup refreshed")
        } else {
            account = Account(
                id: accountId,
                email: email,
                displayName: email,
                provider: .codex,
                subscriptionType: identity.planType,
                providerAccountId: providerId
            )
            accounts.append(account)
            joinActiveProfile(account)
            log.info("[adoptCodexIdentity] Created Codex account \(account.id)")
        }

        for i in accounts.indices where accounts[i].provider == .codex {
            accounts[i].isActive = (accounts[i].id == account.id)
            if accounts[i].id == account.id {
                accounts[i].lastUsed = Date()
            }
        }
        activeCodexAccount = accounts.first { $0.id == account.id }
        saveAccounts()
        recordLastActive(account)
        return true
    }

    /// New accounts join the active profile automatically.
    func joinActiveProfile(_ account: Account) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }),
              !profiles[index].contains(account.id) else { return }
        profiles[index].accountIds.append(account.id)
        saveProfiles()
    }

    /// Remember `account` as the active profile's last-active one for its
    /// provider (only if the profile contains it).
    func recordLastActive(_ account: Account) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }),
              profiles[index].contains(account.id) else { return }
        profiles[index].lastActiveAccountIds[account.provider.rawValue] = account.id
        saveProfiles()
    }

    /// Drop a removed account from every profile, including last-active hints.
    func scrubFromProfiles(_ accountId: UUID) {
        for index in profiles.indices {
            profiles[index].accountIds.removeAll { $0 == accountId }
            profiles[index].lastActiveAccountIds = profiles[index].lastActiveAccountIds.filter { $0.value != accountId }
        }
        saveProfiles()
    }
}
