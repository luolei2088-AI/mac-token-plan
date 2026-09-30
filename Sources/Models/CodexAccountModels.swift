import Foundation

struct CodexAccountSnapshot: Decodable {
    let email: String?
    let planType: String?
    let ordinaryUsageAllowed: Bool?
    let rateLimitResetCredits: CodexResetCredits?
    let rateLimitsByLimitId: [String: CodexRateLimit]?
    let rateLimits: CodexRateLimit?
    let usage: CodexUsageResponse?
    let models: [CodexAvailableModel]
    let modelsError: String?
    let fetchedAt: Date

    var allRateLimits: [CodexRateLimit] {
        if let rateLimitsByLimitId, !rateLimitsByLimitId.isEmpty {
            return rateLimitsByLimitId.values.sorted { ($0.limitId ?? "") < ($1.limitId ?? "") }
        }
        return rateLimits.map { [$0] } ?? []
    }

    var resetCreditCount: Int { rateLimitResetCredits?.availableCount ?? 0 }
}

struct CodexAvailableModel: Decodable, Identifiable {
    var id: String { model }
    let model: String
    let displayName: String
    let description: String
    let hidden: Bool
    let isDefault: Bool
    let inputModalities: [String]?
    let supportedReasoningEfforts: [CodexReasoningEffortOption]
    let defaultReasoningEffort: String?
}

struct CodexReasoningEffortOption: Decodable, Identifiable {
    var id: String { reasoningEffort }
    let reasoningEffort: String
    let description: String
}

struct CodexModelListResponse: Decodable {
    let data: [CodexAvailableModel]
    let nextCursor: String?
}

struct CodexRateLimit: Decodable, Identifiable {
    var id: String { limitId ?? limitName ?? normalModelSlug ?? "codex-limit" }
    let limitId: String?
    let limitName: String?
    let normalModelSlug: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let individualLimit: CodexSpendLimit?
    let spendControlReached: Bool?
    let rateLimitReachedType: String?
    let planType: String?
}

struct CodexRateLimitWindow: Decodable, Identifiable {
    var id: String { "\(windowDurationMins ?? 0)-\(resetsAt ?? 0)" }
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
    var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    var label: String {
        guard let minutes = windowDurationMins else { return "额度窗口" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)天" }
        if minutes % 60 == 0 { return "\(minutes / 60)小时" }
        return "\(minutes)分钟"
    }
}

struct CodexSpendLimit: Decodable {
    let limit: String
    let used: String
    let remainingPercent: Int
    let resetsAt: TimeInterval
    var resetDate: Date { Date(timeIntervalSince1970: resetsAt) }
}

struct CodexResetCredits: Decodable {
    let availableCount: Int
    let credits: [CodexResetCredit]?
}

struct CodexResetCredit: Decodable, Identifiable {
    let id: String
    let resetType: String
    let status: String
    let grantedAt: TimeInterval
    let expiresAt: TimeInterval?
    let title: String?
    let description: String?
    var expiryDate: Date? { expiresAt.map(Date.init(timeIntervalSince1970:)) }
}

struct CodexUsageResponse: Decodable {
    let summary: CodexUsageSummary
    let dailyUsageBuckets: [CodexDailyUsage]?
}

struct CodexUsageSummary: Decodable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct CodexDailyUsage: Decodable, Identifiable {
    var id: String { startDate }
    let startDate: String
    let tokens: Int64
}
