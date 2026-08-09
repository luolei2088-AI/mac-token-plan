import Foundation

/// minimax 月度订阅额度。
/// 接口：GET https://www.minimaxi.com/v1/token_plan/remains，Bearer 认证。
/// 返回按模型（general/video/...）的 5小时窗口 + 7天窗口。无总额度维度。
final class MinimaxProvider: QuotaProvider {
    let id = "minimax"
    let displayName = "MiniMax 月度订阅"
    private let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    func fetchQuota() async throws -> [QuotaBucket] {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured }
        var req = URLRequest(url: URL(string: "https://www.minimaxi.com/v1/token_plan/remains")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderError.httpError((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let body = try dec.decode(MinimaxResponse.self, from: data)
        if let st = body.baseResp?.statusCode, st != 0 {
            throw ProviderError.apiError(body.baseResp?.statusMsg ?? "minimax 错误 \(st)")
        }
        var buckets: [QuotaBucket] = []
        for m in body.modelRemains where m.modelName == "general" {
            if let b = bucket(label: "5小时",
                              total: m.currentIntervalTotalCount,
                              usage: m.currentIntervalUsageCount,
                              remains: m.remainsTime,
                              percent: m.currentIntervalRemainingPercent,
                              resetTime: m.endTime.map { Date(timeIntervalSince1970: $0 / 1000) }) { buckets.append(b) }
            if let b = bucket(label: "7天",
                              total: m.currentWeeklyTotalCount,
                              usage: m.currentWeeklyUsageCount,
                              remains: m.weeklyRemainsTime,
                              percent: m.currentWeeklyRemainingPercent,
                              resetTime: m.weeklyEndTime.map { Date(timeIntervalSince1970: $0 / 1000) }) { buckets.append(b) }
        }
        return buckets
    }

    /// 优先用次数配额；无次数配额时用 remains + percent 反推 used/limit（token 类额度）。
    /// minimax 只展示百分比（percentOnly=true），used/limit 仅用于算进度。
    private func bucket(label: String, total: Int, usage: Int, remains: Double?, percent: Double?, resetTime: Date? = nil) -> QuotaBucket? {
        if total > 0 {
            return QuotaBucket(label: label, used: Double(usage), limit: Double(total), percentOnly: true, resetTime: resetTime)
        }
        if let p = percent, let r = remains {
            if p > 0 {
                let limit = r / (p / 100.0)
                return QuotaBucket(label: label, used: limit - r, limit: limit, percentOnly: true, resetTime: resetTime)
            }
            // 额度已用完：返回满桶，让进度条 100% 红色显示而非整行消失。
            return QuotaBucket(label: label, used: 1, limit: 1, percentOnly: true, resetTime: resetTime)
        }
        return nil
    }
}

private struct MinimaxResponse: Decodable {
    let modelRemains: [ModelRemain]
    let baseResp: BaseResp?
    struct ModelRemain: Decodable {
        let modelName: String
        let currentIntervalTotalCount: Int
        let currentIntervalUsageCount: Int
        let currentIntervalRemainingPercent: Double?
        let remainsTime: Double?
        let endTime: Double?              // 5小时窗口结束=重置
        let currentWeeklyTotalCount: Int
        let currentWeeklyUsageCount: Int
        let currentWeeklyRemainingPercent: Double?
        let weeklyRemainsTime: Double?
        let weeklyEndTime: Double?        // 7天窗口结束=重置
    }
    struct BaseResp: Decodable { let statusCode: Int?; let statusMsg: String? }
}
