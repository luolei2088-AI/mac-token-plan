import Foundation

/// 单个平台的额度快照
struct ProviderQuota: Identifiable {
    let id: String              // "minimax" / "volcengine"
    let displayName: String
    let buckets: [QuotaBucket]  // 5h / 7d / total，按平台支持情况给
    let fetchedAt: Date
    let error: String?          // 非 nil 表示本次拉取失败，UI 标红并保留旧数据
}

/// 单个额度维度（带标签，维度不写死）
struct QuotaBucket: Identifiable {
    /// id 纳入 source，保证同一平台多个同维度窗口（如 Codex 账户 7天 + 模型 7天）不冲突。
    var id: String { source.map { "\($0)·\(label)" } ?? label }
    let label: String           // 纯窗口维度名："5小时" / "7天" / "总额度" / "余额"（维度开关、倒计时判断都依赖它）
    let source: String?         // 额度来源标注（Codex："账户" 或模型短名 "Spark"）；nil 表示该平台不区分来源
    let used: Double
    let limit: Double
    let percentOnly: Bool       // true 时只显示百分比，不显示 used/limit
    let resetTime: Date?        // 重置时间（5h/7d 有，总额度无）
    let balanceAmount: Double?  // 余额类维度：金额值，非 nil 时 UI 显示金额而非进度条
    let currency: String?       // 金额币种："CNY" / "USD"
    /// UI 展示名：带来源时拼 `来源·维度`（如 "Spark·5小时"、"账户·7天"），否则就是 label。
    var displayLabel: String {
        if let s = source, !s.isEmpty { return "\(s)·\(label)" }
        return label
    }
    var remaining: Double { limit - used }
    var percent: Double { limit > 0 ? min(1, max(0, used / limit)) : 0 }
    var currencySymbol: String {
        switch currency {
        case "CNY": return "¥"
        case "USD": return "$"
        case .some(let c): return c + " "
        case nil: return ""
        }
    }
    init(label: String, used: Double, limit: Double, percentOnly: Bool = false, resetTime: Date? = nil,
         balanceAmount: Double? = nil, currency: String? = nil, source: String? = nil) {
        self.label = label
        self.source = source
        self.used = used
        self.limit = limit
        self.percentOnly = percentOnly
        self.resetTime = resetTime
        self.balanceAmount = balanceAmount
        self.currency = currency
    }
}
