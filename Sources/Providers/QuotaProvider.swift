import Foundation

/// 数据源协议：每个订阅平台实现一个。
/// 新增平台 = 新增一个 Provider，不改 Store/UI。
protocol QuotaProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    /// 拉取当前额度各维度。失败时抛错，Store 会保留旧数据并标红。
    func fetchQuota() async throws -> [QuotaBucket]
}

enum ProviderError: Error, LocalizedError {
    case notConfigured
    case httpError(Int)
    case apiError(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "未配置凭证"
        case .httpError(let c): return "请求失败 (HTTP \(c))"
        case .apiError(let m): return m
        }
    }
}
