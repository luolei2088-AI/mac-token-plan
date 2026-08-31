import Foundation
import os.log

/// DeepSeek 开放平台余额。
/// 接口：GET https://api.deepseek.com/user/balance，Bearer 认证。
/// 返回充值余额（字符串金额 + 币种），无 used/limit/百分比/重置时间 —— 走金额桶展示（无进度条）。
/// balance_infos 可能多条（CNY/USD），每条一个桶；CNY 的 label 用「余额」，其他币种带后缀。
/// granted_balance（赠金）/ topped_up_balance（充值余额）暂不单独展示，只显示 total_balance。
final class DeepSeekProvider: QuotaProvider {
    let id = "deepseek"
    let displayName = "DeepSeek"
    private let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    func fetchQuota() async throws -> [QuotaBucket] {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured }
        let keyTail = String(apiKey.suffix(4))
        os_log("deepseek fetch: keyLen=%d keyTail=%{public}@", log: .default, type: .info, apiKey.count, keyTail)
        var req = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if code == 401 || code == 403 {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                os_log("deepseek auth fail http=%d body=%{public}@", log: .default, type: .error, code, bodyText)
                throw ProviderError.apiError("DeepSeek API Key 无效或已失效 (HTTP \(code))")
            }
            throw ProviderError.httpError(code)
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let body = try dec.decode(DeepSeekBalanceResponse.self, from: data)
        guard let infos = body.balanceInfos, !infos.isEmpty else {
            throw ProviderError.apiError("余额数据为空")
        }
        return infos.compactMap { info in
            guard let text = info.totalBalance, let amount = Double(text) else { return nil }
            let cur = info.currency ?? "CNY"
            let label = cur == "CNY" ? "余额" : "余额(\(cur))"
            return QuotaBucket(label: label, used: 0, limit: 0, resetTime: nil,
                               balanceAmount: amount, currency: cur)
        }
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool?    // 账户是否可调用 API；余额<=0 时 UI 已标红，此处不单独处理
    let balanceInfos: [BalanceInfo]?
    struct BalanceInfo: Decodable {
        let currency: String?
        let totalBalance: String?
        let grantedBalance: String?
        let toppedUpBalance: String?
    }
}
