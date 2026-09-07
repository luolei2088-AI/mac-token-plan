import Foundation
import os.log

private let codexLog = OSLog(subsystem: "com.luolei.mac-token-plan", category: "Codex")

/// ChatGPT / Codex 订阅使用量。
/// 接口：GET https://chatgpt.com/backend-api/wham/usage
/// 鉴权：Authorization: Bearer <access_token>（ChatGPT OAuth access token）
/// 凭证获取：优先从本地 codex CLI 的 `~/.codex/auth.json` 读 `tokens.access_token`；
///          缺失时回退到 .env 的 `CODEX_ACCESS_TOKEN`（手动从 chatgpt.com DevTools 提取）。
///
/// 响应结构（2026-09 实测）：
/// - `rate_limit`：账户级主额度窗口。当前 prolite 计划只回 `primary_window`（7 天，604800s），
///   `secondary_window` 为 null（5h 窗口已不在顶层）。
/// - `additional_rate_limits[]`：按模型/特性独立计额的额度池，每个自带 `rate_limit.primary_window`
///   （5 小时，18000s）和 `secondary_window`（7 天）。例如 GPT-5.3-Codex-Spark（codex_bengalfox）。
/// 每个窗口含 `used_percent`（已用百分比 0-100）、`limit_window_seconds`、`reset_at`（unix 秒）。
/// 窗口名按 `limit_window_seconds` 自动判断（5小时/7天）；每条桶带 `source` 标注来源（"账户" / 模型短名）。
/// 展示顺序按来源分组：账户主额度在最上，其下同一模型额度池的 5h/7d 聚拢。
final class CodexProvider: QuotaProvider {
    let id = "codex"
    let displayName = "Codex 订阅"
    private let credentialLoader: () -> CodexCredential?

    init(credentialLoader: @escaping () -> CodexCredential?) {
        self.credentialLoader = credentialLoader
    }

    func fetchQuota() async throws -> [QuotaBucket] {
        guard let credential = credentialLoader(), !credential.accessToken.isEmpty else {
            throw ProviderError.notConfigured
        }
        do {
            return try await fetchQuota(accessToken: credential.accessToken)
        } catch CodexAuthenticationError.rejected(let code) {
            guard let freshCredential = credentialLoader(),
                  !freshCredential.accessToken.isEmpty,
                  freshCredential.accessToken != credential.accessToken else {
                throw Self.authenticationError(statusCode: code)
            }
            do {
                return try await fetchQuota(accessToken: freshCredential.accessToken)
            } catch CodexAuthenticationError.rejected(let retryCode) {
                throw Self.authenticationError(statusCode: retryCode)
            }
        }
    }

    private func fetchQuota(accessToken: String) async throws -> [QuotaBucket] {
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        // 额度数据实时性要求高，禁用本地缓存，避免刷新拿到旧响应。
        req.cachePolicy = .reloadIgnoringLocalCacheData

        os_log("Codex 请求 %@", log: codexLog, type: .debug, url.absoluteString)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            os_log("URLSession failed: %{public}@", log: codexLog, type: .error, "\(error)")
            throw error
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        os_log("Codex 响应 status=%d", log: codexLog, type: .default, code)
        guard code == 200 else {
            if code == 401 || code == 403 {
                throw CodexAuthenticationError.rejected(statusCode: code)
            }
            throw ProviderError.httpError(code)
        }

        let body: CodexResponse
        do {
            body = try JSONDecoder().decode(CodexResponse.self, from: data)
        } catch {
            os_log("JSON decode failed: %{public}@", log: codexLog, type: .error, "\(error)")
            let raw = String(data: data, encoding: .utf8) ?? "<非 UTF8 响应>"
            os_log("Raw response: %{public}@", log: codexLog, type: .error, raw)
            throw ProviderError.apiError("Codex 响应解析失败：\(error.localizedDescription)")
        }

        // 摊平收集所有窗口：顶层账户主额度 + additional_rate_limits 各模型独立额度池。
        // source 标注额度来源（"账户" / 模型短名）；label 保持纯窗口维度名（"5小时"/"7天"），
        // 维度开关（shouldShow）与倒计时判断都依赖纯 label。
        var collected: [(window: CodexResponse.Window, source: String)] = []
        if let rl = body.rateLimit {
            if let w = rl.primaryWindow { collected.append((w, "账户")) }
            if let w = rl.secondaryWindow { collected.append((w, "账户")) }
        }
        for add in body.additionalRateLimits ?? [] {
            let model = Self.shortModelName(add.limitName)
            if let rl = add.rateLimit {
                if let w = rl.primaryWindow { collected.append((w, model)) }
                if let w = rl.secondaryWindow { collected.append((w, model)) }
            }
        }

        // 排序：按额度来源分组——账户主额度在最上，其下同一模型额度池的窗口聚拢；
        // 同组内按窗口时长升序（5h 在前、7d 在后）。模型组之间按接口返回顺序。
        let filtered = collected.filter { $0.window.usedPercent != nil }
        var sourceRank: [String: Int] = ["账户": 0]
        var nextRank = 1
        for c in filtered where sourceRank[c.source] == nil {
            sourceRank[c.source] = nextRank
            nextRank += 1
        }
        let valid = filtered
            .enumerated()
            .sorted { a, b in
                let ra = sourceRank[a.element.source] ?? Int.max
                let rb = sourceRank[b.element.source] ?? Int.max
                if ra != rb { return ra < rb }
                let sa = a.element.window.limitWindowSeconds ?? 0
                let sb = b.element.window.limitWindowSeconds ?? 0
                if sa != sb { return sa < sb }
                return a.offset < b.offset
            }
            .map(\.element)

        guard !valid.isEmpty else {
            throw ProviderError.apiError("Codex 未返回 5h/7d 任一窗口")
        }

        var buckets: [QuotaBucket] = []
        for c in valid {
            guard let usedPct = c.window.usedPercent else { continue }
            let label = Self.label(forSeconds: c.window.limitWindowSeconds ?? 0)
            let resetDate = c.window.resetAt.map { Date(timeIntervalSince1970: $0) }
            buckets.append(QuotaBucket(
                label: label,
                used: usedPct,
                limit: 100,
                percentOnly: true,
                resetTime: resetDate,
                source: c.source
            ))
        }
        os_log("Codex 解析出 %d 个窗口: %@", log: codexLog, type: .default,
               buckets.count, buckets.map { "\($0.displayLabel)=\(Int($0.used))%" }.joined(separator: " "))
        return buckets
    }

    private static func authenticationError(statusCode: Int) -> ProviderError {
        .apiError("Codex 凭证失效（HTTP \(statusCode)），请重新登录 Codex CLI 或更新 .env")
    }

    /// 把窗口秒数翻译成中文标签。固定窗口识别 5h / 7d / 1d；±5% 容差吸收秒数漂移。
    private static func label(forSeconds s: Double) -> String {
        if abs(s - 5 * 3600) < 5 * 3600 * 0.05 { return "5小时" }
        if abs(s - 7 * 86400) < 86400 * 0.05 { return "7天" }
        if abs(s - 86400) < 3600 { return "1天" }
        let hours = Int(s / 3600)
        return "\(hours)小时"
    }

    /// 从 limit_name 提取模型短名作为额度来源标注。
    /// "GPT-5.3-Codex-Spark" → "Spark"（取末段特性名）；末段过短或缺失时回退全名 / "模型"。
    private static func shortModelName(_ limitName: String?) -> String {
        guard let name = limitName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "模型" }
        if let last = name.split(separator: "-").last, last.count >= 2 {
            return String(last)
        }
        return name
    }
}

private enum CodexAuthenticationError: Error {
    case rejected(statusCode: Int)
}

// MARK: - 响应模型
// 字段全 Optional，宽容解析。ChatGPT 后端响应形态在持续迭代（5h 窗口已从顶层挪到 additional_rate_limits）。
private struct CodexResponse: Decodable {
    let rateLimit: RateLimit?
    let additionalRateLimits: [AdditionalRateLimit]?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }

    struct AdditionalRateLimit: Decodable {
        let limitName: String?
        let rateLimit: RateLimit?
        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case rateLimit = "rate_limit"
        }
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
