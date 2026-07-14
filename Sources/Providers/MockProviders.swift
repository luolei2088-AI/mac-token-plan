import Foundation

/// 假数据 Provider，无配置时用于预览 UI。接真实 API 后由真实 Provider 替代。
final class MockMinimaxProvider: QuotaProvider {
    let id = "minimax"
    let displayName = "MiniMax 月度订阅"
    func fetchQuota() async throws -> [QuotaBucket] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return [
            .init(label: "5小时", used: 320_000, limit: 1_000_000),
            .init(label: "7天", used: 2_100_000, limit: 5_000_000),
            .init(label: "总额度", used: 8_400_000, limit: 20_000_000),
        ]
    }
}

final class MockVolcEngineProvider: QuotaProvider {
    let id = "volcengine"
    let displayName = "火山方舟 Agent Plan"
    func fetchQuota() async throws -> [QuotaBucket] {
        try await Task.sleep(nanoseconds: 250_000_000)
        return [
            .init(label: "5小时", used: 120_000, limit: 800_000),
            .init(label: "7天", used: 1_500_000, limit: 6_000_000),
            .init(label: "总额度", used: 5_000_000, limit: 30_000_000),
        ]
    }
}
