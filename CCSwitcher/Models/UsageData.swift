import Foundation

// MARK: - Usage API Response (from /api/oauth/usage)

struct UsageAPIResponse: Codable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOauthApps: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayCowork: UsageWindow?
    let iguanaNecktie: UsageWindow?
    let extraUsage: ExtraUsage?
    let limits: UsageLimitList?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case iguanaNecktie = "iguana_necktie"
        case extraUsage = "extra_usage"
        case limits
    }

    /// Weekly limits that apply to a single model (e.g. Fable), reported only in
    /// the `limits` array as `kind: "weekly_scoped"` with `scope.model.display_name`.
    var modelWeeklyLimits: [ModelScopedLimit] {
        (limits?.items ?? []).compactMap { limit in
            guard limit.kind == "weekly_scoped",
                  let name = limit.scope?.model?.displayName, !name.isEmpty else { return nil }
            return ModelScopedLimit(
                model: name,
                window: UsageWindow(utilization: limit.percent, resetsAt: limit.resetsAt)
            )
        }
    }
}

struct ModelScopedLimit: Identifiable {
    let model: String
    let window: UsageWindow
    var id: String { model }
}

/// The `limits` array is newer and less settled than the legacy window keys, so
/// it decodes leniently: a shape change yields no entries instead of failing
/// the whole usage response (which would also hide the 5h/7d bars).
struct UsageLimitList: Codable {
    let items: [UsageLimit]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        items = (try? container.decode([LossyLimit].self))?.compactMap(\.value) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }

    private struct LossyLimit: Decodable {
        let value: UsageLimit?
        init(from decoder: Decoder) throws {
            value = try? UsageLimit(from: decoder)
        }
    }
}

struct UsageLimit: Codable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind, percent, scope
        case resetsAt = "resets_at"
    }

    struct Scope: Codable {
        let model: Model?
    }

    struct Model: Codable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }
}

struct UsageWindow: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetsAt)
    }

    var resetTimeString: String? {
        guard let date = resetsAtDate else { return nil }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "now" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 24 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE h:mm a"
            return formatter.string(from: date)
        } else if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }

    /// Compact countdown rendering for narrow menu-bar modules.
    /// Always returns a fixed-shape string ("now", "5m", "2h 14m", "4d 6h").
    /// Never falls back to a date format — the menu bar can't afford the width.
    var compactResetString: String? {
        guard let date = resetsAtDate else { return nil }
        let remaining = Int(date.timeIntervalSinceNow)
        guard remaining > 0 else { return "now" }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3600
        let minutes = (remaining % 3600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    /// How much of the rate-limit window has already elapsed, as a 0–100
    /// percentage: `1 − remaining / windowSeconds`, clamped to [0, 100].
    /// `windowSeconds` is the fixed window length (5h = 18000, 7d = 604800).
    /// Returns nil if there's no reset timestamp. Compared against the usage
    /// bar this shows whether you're burning faster or slower than the clock.
    func elapsedPercent(windowSeconds: Double) -> Double? {
        guard windowSeconds > 0, let date = resetsAtDate else { return nil }
        let elapsed = 1.0 - (date.timeIntervalSinceNow / windowSeconds)
        return min(max(elapsed, 0), 1) * 100
    }
}

/// Fixed rate-limit window lengths, in seconds.
enum RateLimitWindow {
    static let fiveHourSeconds: Double = 5 * 60 * 60       // 18,000
    static let sevenDaySeconds: Double = 7 * 24 * 60 * 60  // 604,800
}

struct ExtraUsage: Codable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

// MARK: - Stats Cache (matches ~/.claude/stats-cache.json)

struct StatsCache: Codable {
    let version: Int?
    let lastComputedDate: String?
    let dailyActivity: [DailyActivity]?
    let totalSessions: Int?
    let totalMessages: Int?
    let longestSession: LongestSession?
    let firstSessionDate: String?
    let hourCounts: [String: Int]?
}

struct DailyActivity: Codable, Identifiable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int

    var id: String { date }

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}

struct LongestSession: Codable {
    let sessionId: String?
    let duration: Int?
    let messageCount: Int?
    let timestamp: String?
}

// MARK: - Computed Usage Summary

struct UsageSummary {
    let weeklyMessages: Int
    let weeklySessionCount: Int
    let weeklyToolCalls: Int
    let todayMessages: Int
    let todaySessionCount: Int
    let todayToolCalls: Int
    let totalMessages: Int
    let totalSessions: Int
    let dailyActivity: [DailyActivity]

    static let empty = UsageSummary(
        weeklyMessages: 0,
        weeklySessionCount: 0,
        weeklyToolCalls: 0,
        todayMessages: 0,
        todaySessionCount: 0,
        todayToolCalls: 0,
        totalMessages: 0,
        totalSessions: 0,
        dailyActivity: []
    )
}

// MARK: - Session Info (from ~/.claude/sessions/*.json)

struct SessionInfo: Codable, Identifiable {
    let pid: Int
    let sessionId: String
    let cwd: String?
    let startedAt: Double?

    var id: String { sessionId }

    var startDate: Date? {
        guard let startedAt else { return nil }
        return Date(timeIntervalSince1970: startedAt / 1000)
    }
}
