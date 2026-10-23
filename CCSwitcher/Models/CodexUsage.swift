import Foundation

/// Rate-limit snapshot for a ChatGPT-backed Codex account, as reported by
/// `https://chatgpt.com/backend-api/wham/usage`.
struct CodexUsage: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        /// 0...100.
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: Date?
    }

    let planType: String?
    /// Short window (5 hours).
    let primary: Window?
    /// Long window (weekly).
    let secondary: Window?
    let hasCredits: Bool?
    let unlimitedCredits: Bool?
    let creditsBalance: Double?
}

/// Who a Codex `auth.json` belongs to, decoded from its id_token claims.
struct CodexIdentity: Codable, Equatable, Sendable {
    let email: String?
    let planType: String?
    /// ChatGPT account id (`https://api.openai.com/auth.chatgpt_account_id`);
    /// the stable key for de-duplicating Codex accounts.
    let chatgptAccountId: String?
    /// True when auth.json holds an OPENAI_API_KEY instead of ChatGPT tokens.
    let isApiKey: Bool
    /// Per-user id (`https://api.openai.com/auth.chatgpt_user_id`). Members of
    /// one Team workspace share `chatgptAccountId`, so identity = both ids.
    var chatgptUserId: String? = nil

    /// Stable key for de-duplicating Codex accounts (`Account.providerAccountId`).
    var providerKey: String? {
        guard let chatgptAccountId else { return nil }
        guard let chatgptUserId else { return chatgptAccountId }
        return "\(chatgptUserId):\(chatgptAccountId)"
    }
}

enum CodexServiceError: LocalizedError, Equatable {
    case notInstalled
    case notLoggedIn
    case noStoredCredentials
    case storeUnavailable
    case invalidAuthFile(String)
    /// auth.json holds a login no stored account owns (or an API key over a
    /// ChatGPT account); overwriting it would destroy its only copy.
    case unmanagedLogin(email: String?)
    case loginFailed(String)
    case loginCancelled
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int, body: String)
    case appServerStopFailed(String)
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notInstalled: String(localized: "The codex CLI was not found.", bundle: L10n.bundle)
        case .notLoggedIn: String(localized: "Codex is not logged in.", bundle: L10n.bundle)
        case .noStoredCredentials: String(localized: "No stored Codex credentials for this account.", bundle: L10n.bundle)
        case .storeUnavailable: String(localized: "Credential storage is temporarily unavailable.", bundle: L10n.bundle)
        case .invalidAuthFile(let detail): String(localized: "Invalid Codex auth.json: \(detail)", bundle: L10n.bundle)
        case .unmanagedLogin: String(localized: "Codex is logged in with an account CCSwitcher does not manage. Import it first (Settings → Codex) so switching does not discard it.", bundle: L10n.bundle)
        case .loginFailed(let detail): String(localized: "Codex login failed: \(detail)", bundle: L10n.bundle)
        case .loginCancelled: String(localized: "Codex login was cancelled.", bundle: L10n.bundle)
        case .unauthorized: String(localized: "Codex session expired. Log in again.", bundle: L10n.bundle)
        case .rateLimited: String(localized: "Codex usage endpoint is rate limited.", bundle: L10n.bundle)
        case .http(let status, _): String(localized: "Codex usage request failed (HTTP \(status)).", bundle: L10n.bundle)
        case .appServerStopFailed(let detail): String(localized: "Could not stop the Codex app-server to switch accounts: \(detail)", bundle: L10n.bundle)
        case .notImplemented: String(localized: "Not implemented.", bundle: L10n.bundle)
        }
    }
}
