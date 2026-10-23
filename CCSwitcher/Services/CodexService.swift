import Foundation

private let log = FileLog("CodexService")

/// Manages Codex CLI accounts by swapping `$CODEX_HOME/auth.json`
/// (default `~/.codex/auth.json`), mirroring Lampese/codex-switcher.
///
/// Each account's complete auth.json text is kept verbatim in
/// `CodexCredentialStore`, so unknown keys survive a capture → switch round trip.
actor CodexService {
    static let shared = CodexService()

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let expirySkew: TimeInterval = 60
    private static let loginTimeout: TimeInterval = 5 * 60
    private static let sessionWindowSeconds = 5 * 60 * 60
    private static let weeklyWindowSeconds = 7 * 24 * 60 * 60
    /// Browser-like UA: the default CFNetwork one trips Cloudflare's bot check.
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"

    private let store: CodexCredentialStore
    private let session: URLSession
    private var cachedBinaryPath: String?
    /// When the last login-shell lookup came back empty; see `codexBinaryPath()`.
    private var shellLookupFailedAt: Date?
    private static let shellLookupRetryInterval: TimeInterval = 10 * 60
    private var loginProcess: LoginProcess?

    /// What `discardPendingLogin()` must put back: auth.json as it was before
    /// the last successful `login()`, or nothing if the file did not exist.
    private enum PendingLoginUndo {
        case restore(Data)
        case remove
    }
    private var pendingLoginUndo: PendingLoginUndo?
    /// Accounts removed this session. A refresh that was in flight when the
    /// account was removed must not write its backup back.
    private var removedAccountIds: Set<UUID> = []

    init(store: CodexCredentialStore = .shared) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    // MARK: - Paths

    /// Resolved codex binary path, or nil if the CLI is not installed.
    ///
    /// The login-shell lookup is the slow fallback, so a miss is remembered for
    /// 10 minutes instead of re-spawning `zsh -ilc` on every poll.
    func codexBinaryPath() async -> String? {
        if let cachedBinaryPath, FileManager.default.isExecutableFile(atPath: cachedBinaryPath) {
            return cachedBinaryPath
        }
        let fm = FileManager.default
        var found = Self.curatedCandidates().first { fm.isExecutableFile(atPath: $0) }
        if found == nil { found = Self.nvmCandidates().first { fm.isExecutableFile(atPath: $0) } }
        if found == nil {
            if let failedAt = shellLookupFailedAt, Date().timeIntervalSince(failedAt) < Self.shellLookupRetryInterval {
                return nil
            }
            found = await Self.shellPathLookup()
            shellLookupFailedAt = found == nil ? Date() : nil
        }
        cachedBinaryPath = found
        if let found { log.info("codex binary: \(found)") } else { log.warning("codex binary not found") }
        return found
    }

    /// `$CODEX_HOME` if set, else `~/.codex`.
    nonisolated func codexHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private nonisolated var authFileURL: URL {
        codexHome().appendingPathComponent("auth.json")
    }

    // MARK: - Identity & credentials

    /// Identity of the login currently in auth.json, or nil when there is none.
    func readCurrentIdentity() throws(CodexServiceError) -> CodexIdentity? {
        guard let data = readAuthFileData() else { return nil }
        return Self.identity(of: try Self.parseAuth(data))
    }

    /// Copy the live auth.json into the backup store under `accountId`.
    @discardableResult
    func captureCurrentCredentials(forAccountId accountId: UUID) throws(CodexServiceError) -> CodexIdentity {
        pendingLoginUndo = nil
        guard let data = readAuthFileData() else { throw .notLoggedIn }
        let root = try Self.parseAuth(data)
        guard let identity = Self.identity(of: root) else { throw .notLoggedIn }
        try saveBackup(raw: try Self.serialize(root), accountId: accountId)
        log.info("captured credentials for \(accountId) (apiKey=\(identity.isApiKey))")
        return identity
    }

    func hasStoredCredentials(forAccountId accountId: UUID) -> Bool {
        store.has(accountId.uuidString)
    }

    func removeStoredCredentials(forAccountId accountId: UUID) {
        removedAccountIds.insert(accountId)
        store.remove(accountId.uuidString)
    }

    /// Keep the live account's backup current: Codex rotates tokens in
    /// auth.json in place, and a CLI-side `codex login` would otherwise
    /// discard the only fresh copy. Writes only when the live login belongs
    /// to `accountId` (same `providerKey`) and its content changed.
    /// Returns true when the backup was updated.
    @discardableResult
    func refreshLiveBackupIfChanged(forAccountId accountId: UUID) throws(CodexServiceError) -> Bool {
        guard let liveData = readAuthFileData(), let liveRoot = try? Self.parseAuth(liveData),
              let liveIdentity = Self.identity(of: liveRoot), !liveIdentity.isApiKey,
              let liveKey = liveIdentity.providerKey else { return false }
        let storedRaw: String
        switch store.lookup(accountId.uuidString) {
        case .found(let raw): storedRaw = raw
        case .missing: return false
        case .storeUnavailable: throw .storeUnavailable
        }
        guard let storedData = storedRaw.data(using: .utf8), let storedRoot = try? Self.parseAuth(storedData),
              Self.identity(of: storedRoot)?.providerKey == liveKey else { return false }
        let serialized = try Self.serialize(liveRoot)
        guard serialized != storedRaw else { return false }
        try saveBackup(raw: serialized, accountId: accountId)
        log.info("refreshed backup of \(accountId) from live auth.json")
        return true
    }

    /// Undo the most recent successful `login()`: restore the auth.json that
    /// was live before it (or remove the file if there was none). For callers
    /// that reject the new login after the fact (e.g. API-key logins).
    func discardPendingLogin() throws(CodexServiceError) {
        guard let undo = pendingLoginUndo else { throw .loginFailed("no pending login") }
        switch undo {
        case .restore(let data):
            try writeAuthFile(data)
        case .remove:
            try? FileManager.default.removeItem(at: authFileURL)
        }
        pendingLoginUndo = nil
        log.info("discarded pending login; previous auth.json restored")
    }

    #if DEBUG
    /// Test hook: pretend a `login()` just succeeded over `previous`.
    func setPendingLoginForTesting(previous: Data?) {
        pendingLoginUndo = previous.map { .restore($0) } ?? .remove
    }
    #endif

    // MARK: - Switching

    /// Make `target` live: first re-capture the live auth.json into its
    /// owner's backup (Codex rotates tokens in place), then write the target's
    /// backup to auth.json atomically with mode 0600.
    ///
    /// Ownership rule: the owner of the live login is the stored backup whose
    /// identity has the same `providerKey` (user id + account id). `current` is
    /// only a hint and is never trusted over the key. A live login nobody owns
    /// (unknown login, API key, `current == nil`) throws `.unmanagedLogin` and
    /// changes nothing: overwriting it would destroy its only copy.
    func switchAccount(to target: UUID, from current: UUID?) throws(CodexServiceError) {
        pendingLoginUndo = nil
        // Read the target first: failing here must not have touched anything.
        let targetRaw: String
        switch store.lookup(target.uuidString) {
        case .found(let raw): targetRaw = raw
        case .missing: throw .noStoredCredentials
        case .storeUnavailable: throw .storeUnavailable
        }
        guard let targetData = targetRaw.data(using: .utf8), (try? Self.parseAuth(targetData)) != nil else {
            throw .invalidAuthFile("stored credentials for target are corrupt")
        }

        if let liveData = readAuthFileData(), try recaptureLive(liveData, preferring: current) == target {
            // The live login already is the target, now with its freshest tokens.
            log.info("target \(target) is already live; backup refreshed")
            return
        }

        try writeAuthFile(targetData)
        log.info("switched live auth.json to \(target)")
    }

    /// Re-capture the live file into its owner's backup so rotated tokens are
    /// not lost. Returns the owner, or nil when the file holds nothing worth
    /// keeping (not JSON, or neither tokens nor an API key).
    private func recaptureLive(_ liveData: Data, preferring current: UUID?) throws(CodexServiceError) -> UUID? {
        guard let liveRoot = try? Self.parseAuth(liveData), let liveIdentity = Self.identity(of: liveRoot) else {
            log.warning("live auth.json unusable; nothing to re-capture")
            return nil
        }
        let entries: [String: String]
        switch store.loadAll() {
        case .loaded(let dict): entries = dict
        case .empty: entries = [:]
        case .failed: throw .storeUnavailable
        }

        // Never match on a nil key: API-key logins and key-less files own nothing.
        guard let liveKey = liveIdentity.providerKey else {
            log.warning("live auth.json has no account key; refusing to overwrite it")
            throw .unmanagedLogin(email: liveIdentity.email)
        }
        func key(of raw: String) -> String? {
            guard let data = raw.data(using: .utf8), let root = try? Self.parseAuth(data) else { return nil }
            return Self.identity(of: root)?.providerKey
        }
        var owner: (id: UUID, raw: String)?
        if let current, let raw = entries[current.uuidString], key(of: raw) == liveKey {
            owner = (current, raw)
        } else {
            for (idString, raw) in entries.sorted(by: { $0.key < $1.key }) where key(of: raw) == liveKey {
                if let id = UUID(uuidString: idString) { owner = (id, raw); break }
            }
        }
        guard let owner else {
            log.warning("live auth.json belongs to no stored account; refusing to overwrite it")
            throw .unmanagedLogin(email: liveIdentity.email)
        }
        let serialized = try Self.serialize(liveRoot)
        if serialized != owner.raw { try saveBackup(raw: serialized, accountId: owner.id) }
        return owner.id
    }

    // MARK: - Login

    /// Run `codex login` (browser OAuth). The previous auth.json is restored if
    /// login fails or is cancelled. On success the new login is live in
    /// auth.json; the caller decides which account id to capture it under.
    func login() async throws(CodexServiceError) -> CodexIdentity {
        guard let binary = await codexBinaryPath() else { throw .notInstalled }
        guard loginProcess == nil else { throw .loginFailed("A login is already in progress.") }
        pendingLoginUndo = nil

        let previous = readAuthFileData()
        let handle = LoginProcess()
        loginProcess = handle
        defer { loginProcess = nil }

        log.info("[login] starting `codex login`")
        let status = await handle.run(binary: binary, timeout: Self.loginTimeout)

        func restore() {
            let current = readAuthFileData()
            guard current != previous else { return }
            if let previous {
                try? writeAuthFile(previous)
            } else {
                try? FileManager.default.removeItem(at: authFileURL)
            }
            log.info("[login] restored previous auth.json")
        }

        if handle.wasCancelled {
            restore()
            throw .loginCancelled
        }
        if handle.timedOut {
            restore()
            throw .loginFailed("Timed out waiting for the browser login.")
        }
        guard status == 0 else {
            restore()
            log.error("[login] codex exited \(status)")
            throw .loginFailed(handle.lastLine ?? "codex exited with status \(status)")
        }

        let identity: CodexIdentity?
        do {
            identity = try readCurrentIdentity()
        } catch {
            restore()
            throw error
        }
        guard let identity else {
            restore()
            throw .loginFailed("Login finished but no credentials were written.")
        }
        pendingLoginUndo = previous.map { .restore($0) } ?? .remove
        log.info("[login] success (apiKey=\(identity.isApiKey))")
        return identity
    }

    func cancelLogin() {
        loginProcess?.cancel()
    }

    // MARK: - Usage

    /// Usage for an account. The live account reads tokens from auth.json;
    /// others use their backup, refreshing (and persisting) expired tokens.
    func fetchUsage(forAccountId accountId: UUID, isLive: Bool) async throws(CodexServiceError) -> CodexUsage {
        var root: [String: Any]
        if isLive {
            guard let data = readAuthFileData() else { throw .notLoggedIn }
            root = try Self.parseAuth(data)
        } else {
            root = try loadBackupRoot(accountId)
        }

        guard var tokens = Self.tokens(of: root) else {
            if let identity = Self.identity(of: root), identity.isApiKey {
                return CodexUsage(planType: "api_key", primary: nil, secondary: nil,
                                  hasCredits: nil, unlimitedCredits: nil, creditsBalance: nil)
            }
            throw isLive ? .notLoggedIn : .noStoredCredentials
        }

        // Live tokens belong to the running Codex CLI, which rotates them
        // itself: refreshing here would invalidate its refresh token.
        if !isLive, Self.needsRefresh(tokens) {
            root = try await refresh(root: root, accountId: accountId)
            tokens = Self.tokens(of: root) ?? tokens
        }

        do {
            return try await requestUsage(tokens)
        } catch {
            guard error == .unauthorized, !isLive else { throw error }
            log.info("[usage] 401 for \(accountId); refreshing once")
            let refreshed = try await refresh(root: root, accountId: accountId)
            guard let fresh = Self.tokens(of: refreshed) else { throw .unauthorized }
            return try await requestUsage(fresh)
        }
    }

    private func requestUsage(_ tokens: Tokens) async throws(CodexServiceError) -> CodexUsage {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Referer")
        request.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("same-origin", forHTTPHeaderField: "sec-fetch-site")
        if let accountId = tokens.accountId {
            request.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        }

        let (data, http) = try await send(request)
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw .unauthorized
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw .rateLimited(retryAfter: retry)
        default:
            // 403 is typically a Cloudflare challenge, not a stale token: no refresh.
            throw .http(status: http.statusCode, body: Self.snippet(data))
        }

        guard let payload = try? JSONDecoder().decode(UsagePayload.self, from: data) else {
            throw .http(status: http.statusCode, body: "undecodable usage response")
        }
        return Self.convert(payload)
    }

    private func send(_ request: URLRequest) async throws(CodexServiceError) -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CodexServiceError.http(status: 0, body: "non-HTTP response")
            }
            return (data, http)
        } catch let error as CodexServiceError {
            throw error
        } catch {
            throw .http(status: 0, body: error.localizedDescription)
        }
    }

    // MARK: - Token refresh (backup accounts only)

    /// Refresh the OAuth tokens in `root` and persist them to the backup
    /// BEFORE returning: refresh tokens are single-use, so a rotated one that
    /// is only held in memory is a logged-out account.
    private func refresh(root: [String: Any], accountId: UUID) async throws(CodexServiceError) -> [String: Any] {
        guard let current = Self.tokens(of: root), !current.refreshToken.isEmpty else { throw .unauthorized }

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            ("grant_type", "refresh_token"),
            ("refresh_token", current.refreshToken),
            ("client_id", Self.clientId),
        ]).data(using: .utf8)

        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            log.error("[refresh] \(accountId) failed: HTTP \(http.statusCode)")
            // invalid_grant / reused token: the user has to log in again.
            if http.statusCode == 400 || http.statusCode == 401 { throw .unauthorized }
            throw .http(status: http.statusCode, body: Self.snippet(data))
        }
        guard let response = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw .http(status: http.statusCode, body: "undecodable refresh response")
        }

        // merge_refresh_response: keep the old id_token unless the new one is usable.
        let now = Date()
        var idToken = current.idToken
        var idTokenUsable = !Self.idTokenNeedsRefresh(current.idToken, now: now)
        if let new = response.idToken, !Self.idTokenNeedsRefresh(new, now: now) {
            idToken = new
            idTokenUsable = true
        }
        let refreshToken = response.refreshToken ?? current.refreshToken
        let claims = CodexJWT.claims(idToken)

        var next = root
        var tokensDict = (root["tokens"] as? [String: Any]) ?? [:]
        tokensDict["id_token"] = idToken
        tokensDict["access_token"] = response.accessToken
        tokensDict["refresh_token"] = refreshToken
        if let id = claims.accountId ?? current.accountId { tokensDict["account_id"] = id }
        next["tokens"] = tokensDict
        next["last_refresh"] = Self.timestamp(now)

        try saveBackup(raw: try Self.serialize(next), accountId: accountId)
        log.info("[refresh] \(accountId) refreshed and persisted")

        // The account may have become live while the request was in flight
        // (actor methods interleave at awaits). Its auth.json then still holds
        // the refresh token we just burned; carry the new tokens over.
        syncLiveIfStale(oldRefreshToken: current.refreshToken, next: next)

        guard idTokenUsable else {
            // Tokens are saved so a retry can recover; this refresh is not usable now.
            throw .unauthorized
        }
        return next
    }

    private func syncLiveIfStale(oldRefreshToken: String, next: [String: Any]) {
        guard let data = readAuthFileData(), let live = try? Self.parseAuth(data),
              let liveTokens = Self.tokens(of: live), liveTokens.refreshToken == oldRefreshToken,
              let raw = try? Self.serialize(next), let out = raw.data(using: .utf8) else { return }
        try? writeAuthFile(out)
        log.info("[refresh] account became live mid-refresh; updated auth.json")
    }

    // MARK: - Processes

    /// Number of running `codex` processes. A running session can rewrite
    /// auth.json with its own refreshed tokens and undo a switch.
    ///
    /// Counts interactive CLI sessions (a tty) and the Codex desktop app; like
    /// codex-switcher it ignores `codex app-server` helpers, headless
    /// processes and codex-switcher itself.
    func runningCodexProcessCount() async -> Int {
        guard let result = await CapturedProcess().run(executable: "/bin/ps", arguments: ["-axo", "pid=,tty=,command="], timeout: 5) else {
            log.warning("[processCount] ps failed or timed out")
            return 0
        }
        let data = result.output

        let ownPid = ProcessInfo.processInfo.processIdentifier
        var count = 0
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]) else { continue }
            if pid == ownPid { continue }
            let tty = String(parts[1])
            let command = String(parts[2])
            let lower = command.lowercased()
            if lower.contains("codex-switcher") || lower.contains("codex switcher") || lower.contains("ccswitcher") { continue }
            if lower.contains("app-server") { continue }

            let first = command.split(separator: " ").first.map(String.init) ?? ""
            let isCLI = first == "codex" || first.hasSuffix("/codex")
            let isDesktop = command.contains("/Codex.app/Contents/MacOS/Codex") && !lower.contains("helper")
            if isDesktop || (isCLI && tty != "??" && tty != "?") { count += 1 }
        }
        return count
    }

    // MARK: - auth.json I/O

    private func readAuthFileData() -> Data? {
        FileManager.default.contents(atPath: authFileURL.path)
    }

    /// Temp file in the same directory + rename, mode 0600: a crash mid-write
    /// can never leave a half-written auth.json.
    private func writeAuthFile(_ data: Data) throws(CodexServiceError) {
        let fm = FileManager.default
        let dir = codexHome()
        let temp = dir.appendingPathComponent(".auth.json.ccswitcher-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard rename(temp.path, authFileURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: temp)
            log.error("[writeAuthFile] failed: \(error.localizedDescription)")
            throw .invalidAuthFile("could not write auth.json: \(error.localizedDescription)")
        }
    }

    private func saveBackup(raw: String, accountId: UUID) throws(CodexServiceError) {
        guard !removedAccountIds.contains(accountId) else {
            log.warning("refusing to save a backup for removed account \(accountId)")
            throw .noStoredCredentials
        }
        guard store.save(rawAuth: raw, forAccountId: accountId.uuidString) else { throw .storeUnavailable }
    }

    private func loadBackupRoot(_ accountId: UUID) throws(CodexServiceError) -> [String: Any] {
        switch store.lookup(accountId.uuidString) {
        case .found(let raw):
            guard let data = raw.data(using: .utf8) else { throw .invalidAuthFile("stored credentials are corrupt") }
            return try Self.parseAuth(data)
        case .missing: throw .noStoredCredentials
        case .storeUnavailable: throw .storeUnavailable
        }
    }
}

// MARK: - Auth model helpers

private extension CodexService {
    struct Tokens {
        let idToken: String
        let accessToken: String
        let refreshToken: String
        let accountId: String?
    }

    /// Parsed as a raw object (not a typed struct) so unknown keys round-trip.
    static func parseAuth(_ data: Data) throws(CodexServiceError) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw .invalidAuthFile("not a JSON object")
        }
        return root
    }

    static func serialize(_ root: [String: Any]) throws(CodexServiceError) -> String {
        // Compact output: the store item must stay single-line (see CodexCredentialStore).
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else {
            throw .invalidAuthFile("could not serialize auth data")
        }
        return text
    }

    static func tokens(of root: [String: Any]) -> Tokens? {
        guard let dict = root["tokens"] as? [String: Any],
              let id = dict["id_token"] as? String,
              let access = dict["access_token"] as? String,
              let refresh = dict["refresh_token"] as? String else { return nil }
        return Tokens(idToken: id, accessToken: access, refreshToken: refresh, accountId: dict["account_id"] as? String)
    }

    static func identity(of root: [String: Any]) -> CodexIdentity? {
        if let tokens = tokens(of: root) {
            let claims = CodexJWT.claims(tokens.idToken)
            return CodexIdentity(email: claims.email, planType: claims.planType,
                                 chatgptAccountId: claims.accountId ?? tokens.accountId, isApiKey: false,
                                 chatgptUserId: claims.userId)
        }
        if let key = root["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return CodexIdentity(email: nil, planType: "api_key", chatgptAccountId: nil, isApiKey: true)
        }
        return nil
    }

    static func needsRefresh(_ tokens: Tokens, now: Date = Date()) -> Bool {
        idTokenNeedsRefresh(tokens.idToken, now: now) || accessTokenNeedsRefresh(tokens.accessToken, now: now)
    }

    /// Unreadable id_token counts as needing refresh (as in codex-switcher).
    static func idTokenNeedsRefresh(_ token: String, now: Date) -> Bool {
        guard let exp = CodexJWT.expiry(token) else { return true }
        return exp <= now.addingTimeInterval(expirySkew)
    }

    /// Unreadable access token (opaque, non-JWT) is assumed valid; a 401 triggers the refresh.
    static func accessTokenNeedsRefresh(_ token: String, now: Date) -> Bool {
        guard let exp = CodexJWT.expiry(token) else { return false }
        return exp <= now.addingTimeInterval(expirySkew)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func formBody(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    /// Short response excerpt for errors. Bodies of token endpoints can echo
    /// credentials, so only the status-bearing start is kept.
    static func snippet(_ data: Data) -> String {
        String(String(decoding: data, as: UTF8.self).prefix(200))
    }
}

// MARK: - Usage payload (api/usage.rs, types.rs RateLimitStatusPayload)

private extension CodexService {
    struct UsagePayload: Decodable {
        let planType: String?
        let rateLimit: RateLimit?
        let credits: Credits?

        enum CodingKeys: String, CodingKey { case planType = "plan_type", rateLimit = "rate_limit", credits }
    }

    struct RateLimit: Decodable {
        let primaryWindow: RateWindow?
        let secondaryWindow: RateWindow?

        enum CodingKeys: String, CodingKey { case primaryWindow = "primary_window", secondaryWindow = "secondary_window" }
    }

    struct RateWindow: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAt: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent", limitWindowSeconds = "limit_window_seconds", resetAt = "reset_at"
        }
    }

    struct Credits: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let balance: Double?

        enum CodingKeys: String, CodingKey { case hasCredits = "has_credits", unlimited, balance }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = try? c.decodeIfPresent(Bool.self, forKey: .hasCredits)
            unlimited = try? c.decodeIfPresent(Bool.self, forKey: .unlimited)
            // The backend sends the balance as a string ("0") but tolerate a number.
            if let s = try? c.decodeIfPresent(String.self, forKey: .balance) {
                balance = Double(s)
            } else {
                balance = try? c.decodeIfPresent(Double.self, forKey: .balance)
            }
        }
    }

    struct RefreshResponse: Decodable {
        let idToken: String?
        let accessToken: String
        let refreshToken: String?

        enum CodingKeys: String, CodingKey { case idToken = "id_token", accessToken = "access_token", refreshToken = "refresh_token" }
    }

    static func convert(_ payload: UsagePayload) -> CodexUsage {
        var primary = payload.rateLimit?.primaryWindow
        var secondary = payload.rateLimit?.secondaryWindow
        // The backend may drop the 5h window and promote the weekly one into
        // primary (or swap them). Keep primary = session, secondary = weekly.
        func isSession(_ w: RateWindow?) -> Bool { w?.limitWindowSeconds == sessionWindowSeconds }
        func isWeekly(_ w: RateWindow?) -> Bool { w?.limitWindowSeconds == weeklyWindowSeconds }
        switch (primary, secondary) {
        case (.some(let p), nil) where isWeekly(p): (primary, secondary) = (nil, p)
        case (nil, .some(let s)) where isSession(s): (primary, secondary) = (s, nil)
        case (.some(let p), .some(let s)) where isWeekly(p) && isSession(s): (primary, secondary) = (s, p)
        default: break
        }

        func window(_ w: RateWindow?) -> CodexUsage.Window? {
            guard let w else { return nil }
            return CodexUsage.Window(
                usedPercent: w.usedPercent,
                windowMinutes: w.limitWindowSeconds.map { ($0 + 59) / 60 },
                resetsAt: w.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
        return CodexUsage(
            planType: payload.planType,
            primary: window(primary),
            secondary: window(secondary),
            hasCredits: payload.credits?.hasCredits,
            unlimitedCredits: payload.credits?.unlimited,
            creditsBalance: payload.credits?.balance
        )
    }
}

// MARK: - JWT (no signature verification: we only read our own tokens' claims)

enum CodexJWT {
    struct Claims {
        var email: String?
        var planType: String?
        var accountId: String?
        var userId: String?
    }

    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    static func claims(_ idToken: String) -> Claims {
        guard let json = payload(idToken) else { return Claims() }
        let auth = json["https://api.openai.com/auth"] as? [String: Any]
        return Claims(
            email: json["email"] as? String,
            planType: auth?["chatgpt_plan_type"] as? String,
            accountId: auth?["chatgpt_account_id"] as? String,
            userId: (auth?["chatgpt_user_id"] as? String) ?? (auth?["user_id"] as? String)
        )
    }

    static func expiry(_ token: String) -> Date? {
        guard let exp = payload(token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }
}

// MARK: - Binary discovery (mirrors ClaudeService)

private extension CodexService {
    static func curatedCandidates() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/opt/local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.volta/bin/codex",
            "\(home)/Library/pnpm/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.yarn/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]
    }

    /// NVM keeps node versions at ~/.nvm/versions/node/<version>/bin/.
    static func nvmCandidates() -> [String] {
        let dir = "\(NSHomeDirectory())/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return versions.filter { !$0.hasPrefix(".") }.sorted().map { "\(dir)/\($0)/bin/codex" }
    }

    /// Last resort: ask the login shell. Bounded so a slow .zshrc cannot hang the caller.
    static func shellPathLookup() async -> String? {
        guard let result = await CapturedProcess().run(executable: "/bin/zsh", arguments: ["-ilc", "command -v codex"], timeout: 3) else {
            log.warning("[shellPathLookup] zsh failed or exceeded 3s; aborting")
            return nil
        }
        guard result.status == 0 else { return nil }
        let raw = String(decoding: result.output, as: UTF8.self)
        let candidate = raw.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard candidate.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: candidate) else { return nil }
        return candidate
    }
}

// MARK: - One-shot captured process

/// Runs a short command and collects stdout without blocking a thread: the
/// termination handler and pipe EOF settle a continuation, and a watchdog task
/// kills the process after `timeout` (result nil).
private final class CapturedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var data = Data()
    private var status: Int32?
    private var eof = false
    private var finished = false
    private var continuation: CheckedContinuation<(status: Int32, output: Data)?, Never>?

    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> (status: Int32, output: Data)? {
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.received(chunk)
        }
        process.terminationHandler = { [weak self] finished in
            self?.terminated(finished.terminationStatus)
        }
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.timeOut()
        }
        let result = await withCheckedContinuation { (next: CheckedContinuation<(status: Int32, output: Data)?, Never>) in
            lock.lock(); continuation = next; lock.unlock()
            do {
                try process.run()
            } catch {
                log.warning("[process] launch of \(executable) failed: \(error.localizedDescription)")
                settle(nil)
            }
        }
        watchdog.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        return result
    }

    private func received(_ chunk: Data) {
        lock.lock()
        if chunk.isEmpty { eof = true } else { data.append(chunk) }
        let ready = eof && status != nil
        lock.unlock()
        if ready { settleWithOutput() }
    }

    private func terminated(_ code: Int32) {
        lock.lock()
        status = code
        let ready = eof
        lock.unlock()
        if ready { settleWithOutput() }
    }

    private func settleWithOutput() {
        lock.lock()
        let result = status.map { (status: $0, output: data) }
        lock.unlock()
        settle(result)
    }

    private func timeOut() {
        if process.isRunning { process.terminate() }
        settle(nil)
    }

    private func settle(_ result: (status: Int32, output: Data)?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let next = continuation
        continuation = nil
        lock.unlock()
        next?.resume(returning: result)
    }
}

// MARK: - `codex login` process

/// Owns one `codex login` run. Reference type with a lock so `cancelLogin()`
/// (actor) and the termination handler (arbitrary thread) can both touch it.
private final class LoginProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOutFlag = false
    private var tail = ""

    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOutFlag }
    /// Last non-empty output line, for the error message. Never logged:
    /// login output contains the OAuth URL.
    var lastLine: String? {
        lock.lock(); defer { lock.unlock() }
        return tail.split(whereSeparator: \.isNewline).last.map { String($0.prefix(200)) }
    }

    private func markTimedOut() {
        lock.lock(); defer { lock.unlock() }
        timedOutFlag = true
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }

    /// Returns the exit status; -1 when the process could not be launched.
    func run(binary: String, timeout: TimeInterval) async -> Int32 {
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["login"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        // The binary's own directory must be on PATH so an NVM-installed
        // `codex` finds `node` (same approach as ClaudeService.runClaude).
        var extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin"]
        let resolved = URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
        extra.insert(URL(fileURLWithPath: resolved).deletingLastPathComponent().path, at: 0)
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        env["HOME"] = home
        process.environment = env

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.lock.lock()
            self.tail = String((self.tail + String(decoding: data, as: UTF8.self)).suffix(2048))
            self.lock.unlock()
        }

        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, self.process.isRunning else { return }
            self.markTimedOut()
            self.process.terminate()
        }

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                log.error("[login] launch failed: \(error.localizedDescription)")
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
        watchdog.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        return status
    }
}
