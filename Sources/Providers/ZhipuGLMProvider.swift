import Foundation
import os.log

private let zhipuLog = OSLog(subsystem: "com.luolei.mac-token-plan", category: "ZhipuGLM")

/// 智谱 GLM Coding Plan 额度。
/// 接口：GET https://open.bigmodel.cn/api/monitor/usage/quota/limit
/// 鉴权：Authorization: Bearer <token>
/// 返回：data.limits[]，按 type 区分桶：TIME_LIMIT → "5小时"、TOKENS_LIMIT → "总额度"（多条追加 ·N）。
final class ZhipuGLMProvider: QuotaProvider {
    let id = "zhipu_glm"
    let displayName = "智谱 GLM Coding Plan"
    private let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    func fetchQuota() async throws -> [QuotaBucket] {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured }

        var req = URLRequest(url: URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            os_log("URLSession failed: %{public}@", log: zhipuLog, type: .error, "\(error)")
            throw error
        }
        let httpCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard httpCode == 200 else { throw ProviderError.httpError(httpCode) }

        let body: ZhipuResponse
        do {
            body = try JSONDecoder().decode(ZhipuResponse.self, from: data)
        } catch {
            os_log("JSON decode failed: %{public}@", log: zhipuLog, type: .error, "\(error)")
            throw ProviderError.apiError("JSON 解析失败: \(error)")
        }
        guard body.code == 200 else {
            throw ProviderError.apiError(body.msg ?? "zhipu 错误 \(body.code ?? -1)")
        }
        guard let limits = body.data?.limits, !limits.isEmpty else {
            throw ProviderError.apiError("额度数据为空")
        }

        // 显示顺序：TIME_LIMIT 在前（5小时窗口），后跟 TOKENS_LIMIT（总额度）
        var buckets: [QuotaBucket] = []
        let displayOrder: [String] = ["TIME_LIMIT", "TOKENS_LIMIT"]
        for type in displayOrder {
            let sameTypeCount = limits.filter { $0.type == type }.count
            var posInType = 0
            for limit in limits where limit.type == type {
                guard let pct = limit.percentage else { continue }
                posInType += 1
                let baseLabel: String
                switch type {
                case "TIME_LIMIT":   baseLabel = "5小时"
                case "TOKENS_LIMIT": baseLabel = "总额度"
                default: continue
                }
                let label = sameTypeCount > 1 ? "\(baseLabel)·\(posInType)" : baseLabel
                let resetTime = limit.nextResetTime.map { Date(timeIntervalSince1970: $0 / 1000) }
                buckets.append(QuotaBucket(label: label, used: pct, limit: 100, percentOnly: true, resetTime: resetTime))
            }
        }
        return buckets
    }
}

private struct ZhipuResponse: Decodable {
    let code: Int?
    let msg: String?
    let success: Bool?
    let data: Data?
    struct Data: Decodable {
        let level: String?
        let limits: [Limit]?
    }
    struct Limit: Decodable {
        let type: String
        let unit: Int?
        let number: Int?
        let percentage: Double?
        let usage: Double?
        let currentValue: Double?
        let remaining: Double?
        let nextResetTime: Double?
    }
}
