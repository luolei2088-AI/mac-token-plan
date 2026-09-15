import Foundation

final class BailianTokenPlanProvider: QuotaProvider {
    let id = "bailian_token_plan"
    let displayName = "百炼 Token Plan"
    typealias Runner = (URL, [String], [String: String]) async throws -> CLIResult
    private let runner: Runner
    private let executable: () -> URL?
    static let arguments = ["usage", "token-plan", "--console-region", "cn-beijing", "--console-site", "domestic", "--output", "json"]

    init(executable: @escaping () -> URL? = { CLITool.bailian.resolve() },
         runner: @escaping Runner = { url, args, env in
             try await CLIProcess().run(url, arguments: args, environment: env)
         }) {
        self.executable = executable
        self.runner = runner
    }

    func fetchQuota() async throws -> [QuotaBucket] {
        guard let url = executable() else { throw CLIError.message("未找到百炼 CLI，请在设置中安装或选择路径") }
        let result = try await runner(url, Self.arguments, CLITool.environment(executable: url))
        guard result.status == 0 else {
            throw CLIError.message("百炼查询失败，请检查网络及 Console 登录状态，必要时重新登录")
        }
        return try Self.parse(result.output)
    }

    static func parse(_ data: Data) throws -> [QuotaBucket] {
        struct Usage: Decodable {
            var per5HourPercentage: Double?
            var per5HourResetTime: Double?
            var per1WeekPercentage: Double?
            var per1WeekResetTime: Double?
        }
        guard let usage = try? JSONDecoder().decode(Usage.self, from: data) else {
            throw CLIError.message("百炼额度响应格式无效，请检查 CLI 版本")
        }
        let windows: [(String, Double?, Double?)] = [
            ("5小时", usage.per5HourPercentage, usage.per5HourResetTime),
            ("7天", usage.per1WeekPercentage, usage.per1WeekResetTime)
        ]
        let buckets = windows.compactMap { label, ratio, reset -> QuotaBucket? in
            guard let ratio, ratio.isFinite, ratio >= 0, (ratio * 100).isFinite else { return nil }
            let date = reset.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            return QuotaBucket(label: label, used: ratio * 100, limit: 100, percentOnly: true, resetTime: date)
        }
        guard !buckets.isEmpty else { throw CLIError.message("未返回个人版额度，请确认已订阅中国站个人版 Token Plan") }
        return buckets
    }
}
