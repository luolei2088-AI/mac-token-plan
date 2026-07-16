import Foundation
import os.log

private let codexLog = OSLog(subsystem: "com.luolei.mac-token-plan", category: "Codex")

/// ChatGPT / Codex 订阅使用量。
/// 接口：GET https://chatgpt.com/backend-api/wham/usage
/// 鉴权：Authorization: Bearer <access_token>（ChatGPT OAuth access token）
/// 凭证获取：优先从本地 codex CLI 的 `~/.codex/auth.json` 读 `tokens.access_token`；
///          缺失时回退到 .env 的 `CODEX_ACCESS_TOKEN`（手动从 chatgpt.com DevTools 提取）。
///
/// 响应：`rate_limit.{primary,secondary}_window`，每个窗口含 `used_percent`（已用百分比 0-100）、
///       `limit_window_seconds`（窗口时长，604800=7天、18000=5小时）、`reset_at`（unix 秒）。
/// Plus 计划通常只返回 primary_window（7 天），Pro/Team 可能同时返回 5h + 7d 两个窗口。
/// 不硬编码窗口名，按 `limit_window_seconds` 自动判断标签。
final class CodexProvider: QuotaProvider {
    let id = "codex"
    let displayName = "Codex 订阅"
    private let accessToken: String

    init(accessToken: String) { self.accessToken = accessToken }

    func fetchQuota() async throws -> [QuotaBucket] {
        guard !accessToken.isEmpty else { throw ProviderError.notConfigured }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            os_log("URLSession failed: %{public}@", log: codexLog, type: .error, "\(error)")
            throw error
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else {
            if code == 401 || code == 403 {
                throw ProviderError.apiError("Codex 凭证失效（HTTP \(code)），请重新提取 access token")
            }
            throw ProviderError.httpError(code)
        }

        let body: CodexResponse
        do {
            body = try JSONDecoder().decode(CodexResponse.self, from: data)
        } catch {
            os_log("JSON decode failed: %{public}@", log: codexLog, type: .error, "\(error)")
            throw ProviderError.apiError("Codex 响应解析失败：\(error.localizedDescription)")
        }
        guard let rateLimit = body.rateLimit else {
            throw ProviderError.apiError("Codex 响应未包含 rate_limit")
        }

        // 解析两个窗口，按 limit_window_seconds 决定 label
        var buckets: [QuotaBucket] = []
        for window in [rateLimit.primaryWindow, rateLimit.secondaryWindow] {
            guard let w = window,
                  let usedPct = w.usedPercent else { continue }
            let label = Self.label(forSeconds: w.limitWindowSeconds ?? 0)
            let resetDate = w.resetAt.map { Date(timeIntervalSince1970: $0) }
            buckets.append(QuotaBucket(
                label: label,
                used: usedPct,
                limit: 100,
                percentOnly: true,
                resetTime: resetDate
            ))
        }
        if buckets.isEmpty {
            throw ProviderError.apiError("Codex 未返回 5h/7d 任一窗口")
        }
        return buckets
    }

    /// 把窗口秒数翻译成中文标签。固定窗口识别 5h / 7d / 1d；±5% 容差吸收秒数漂移。
    private static func label(forSeconds s: Double) -> String {
        if abs(s - 5 * 3600) < 5 * 3600 * 0.05 { return "5小时" }
        if abs(s - 7 * 86400) < 86400 * 0.05 { return "7天" }
        if abs(s - 86400) < 3600 { return "1天" }
        let hours = Int(s / 3600)
        return "\(hours)小时"
    }
}

// MARK: - 响应模型
// 字段全 Optional，宽容解析。ChatGPT 后端响应形态可能在迭代中调整。
private struct CodexResponse: Decodable {
    let rateLimit: RateLimit?
    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }
    struct Window: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Double?
        let resetAt: Double?
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }
    }
}