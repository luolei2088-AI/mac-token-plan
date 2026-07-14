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
    var id: String { label }
    let label: String           // "5小时" / "7天" / "总额度"
    let used: Double
    let limit: Double
    let percentOnly: Bool       // true 时只显示百分比，不显示 used/limit
    let resetTime: Date?        // 重置时间（5h/7d 有，总额度无）
    var remaining: Double { limit - used }
    var percent: Double { limit > 0 ? min(1, max(0, used / limit)) : 0 }
    init(label: String, used: Double, limit: Double, percentOnly: Bool = false, resetTime: Date? = nil) {
        self.label = label
        self.used = used
        self.limit = limit
        self.percentOnly = percentOnly
        self.resetTime = resetTime
    }
}
