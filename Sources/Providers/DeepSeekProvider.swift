import Foundation
import os.log

/// DeepSeek API balance and available model catalog.
final class DeepSeekProvider: QuotaProvider {
    let id = "deepseek"
    let displayName = "DeepSeek"
    private let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    func fetchQuota() async throws -> [QuotaBucket] {
        let balance = try await fetchBalance()
        guard let infos = balance.balanceInfos, !infos.isEmpty else {
            throw ProviderError.apiError("余额数据为空")
        }
        return infos.compactMap { info in
            guard let text = info.totalBalance, let amount = Double(text) else { return nil }
            let currency = info.currency ?? "CNY"
            let label = currency == "CNY" ? "余额" : "余额(\(currency))"
            return QuotaBucket(label: label, used: 0, limit: 0, resetTime: nil,
                               balanceAmount: amount, currency: currency)
        }
    }

    func fetchDetails() async throws -> DeepSeekAccountSnapshot {
        async let balance = fetchBalance()
        async let modelList: DeepSeekModelsResponse? = try? fetchModels()
        let balanceResponse = try await balance
        let modelsResponse = await modelList
        return DeepSeekAccountSnapshot(isAvailable: balanceResponse.isAvailable,
                                       balanceInfos: balanceResponse.balanceInfos ?? [],
                                       models: modelsResponse?.data ?? [],
                                       modelsError: modelsResponse == nil ? "模型列表暂不可用" : nil,
                                       fetchedAt: Date())
    }

    private func fetchBalance() async throws -> DeepSeekBalanceResponse {
        try await get("https://api.deepseek.com/user/balance")
    }

    private func fetchModels() async throws -> DeepSeekModelsResponse {
        try await get("https://api.deepseek.com/models")
    }

    private func get<Response: Decodable>(_ endpoint: String) async throws -> Response {
        guard !apiKey.isEmpty else { throw ProviderError.notConfigured }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            if status == 401 || status == 403 {
                throw ProviderError.apiError("DeepSeek API Key 无效或已失效 (HTTP \(status))")
            }
            throw ProviderError.httpError(status)
        }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Response.self, from: data)
        } catch {
            os_log("DeepSeek 响应解析失败: %{public}@", log: .default, type: .error, error.localizedDescription)
            throw ProviderError.apiError("DeepSeek 响应解析失败：\(error.localizedDescription)")
        }
    }
}

struct DeepSeekAccountSnapshot {
    let isAvailable: Bool?
    let balanceInfos: [DeepSeekBalanceInfo]
    let models: [DeepSeekAvailableModel]
    let modelsError: String?
    let fetchedAt: Date
}

struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool?
    let balanceInfos: [DeepSeekBalanceInfo]?
}

struct DeepSeekBalanceInfo: Decodable, Identifiable {
    var id: String { currency ?? "unknown-currency" }
    let currency: String?
    let totalBalance: String?
    let grantedBalance: String?
    let toppedUpBalance: String?
}

struct DeepSeekModelsResponse: Decodable {
    let data: [DeepSeekAvailableModel]
}

struct DeepSeekAvailableModel: Decodable, Identifiable {
    var id: String { modelID }
    let modelID: String
    let name: String?
    let contextWindow: Int?
    let maxOutputTokens: Int?
    let inputModalities: [String]?
    let outputModalities: [String]?
    let effort: DeepSeekModelEffort?

    enum CodingKeys: String, CodingKey {
        case modelID = "id"
        case name
        case contextWindow
        case maxOutputTokens
        case inputModalities
        case outputModalities
        case effort
    }
}

struct DeepSeekModelEffort: Decodable {
    let supportedLevels: [String]?
    let defaultLevel: String?
}
