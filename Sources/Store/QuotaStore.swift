import Foundation
import SwiftUI

/// 额度数据中枢：持有 Provider 列表，定时刷新、缓存、错误降级。
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var quotas: [ProviderQuota] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private var interval: TimeInterval = 300
    private var providers: [QuotaProvider] = []

    var lastUpdatedText: String {
        guard let d = lastUpdated else { return "未刷新" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "更新于 \(f.string(from: d))"
    }

    /// 注入 Provider（由 AppDelegate 在配置或开关变化时调用）。
    func configure(providers: [QuotaProvider]) {
        self.providers = providers
    }

    func setRefreshInterval(_ v: TimeInterval) {
        interval = v
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: v, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func start() {
        refresh()
        if timer == nil { setRefreshInterval(interval) }
    }

    func refresh() {
        guard !isRefreshing, !providers.isEmpty else { return }
        isRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            await self.fetchAll()
            self.isRefreshing = false
            self.lastUpdated = Date()
        }
    }

    /// 并发拉取所有 Provider；失败的保留旧 buckets 并置 error，不闪空。
    private func fetchAll() async {
        let snapshot = providers
        let fetched = await withTaskGroup(of: ProviderQuota?.self) { group in
            for p in snapshot {
                group.addTask {
                    do {
                        let buckets = try await p.fetchQuota()
                        return ProviderQuota(id: p.id, displayName: p.displayName,
                                             buckets: buckets, fetchedAt: Date(), error: nil)
                    } catch {
                        return ProviderQuota(id: p.id, displayName: p.displayName,
                                             buckets: [], fetchedAt: Date(),
                                             error: error.localizedDescription)
                    }
                }
            }
            var out: [ProviderQuota] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
        var merged: [ProviderQuota] = []
        for r in fetched {
            if r.error != nil, let old = quotas.first(where: { $0.id == r.id }), !old.buckets.isEmpty {
                merged.append(ProviderQuota(id: r.id, displayName: r.displayName,
                                            buckets: old.buckets, fetchedAt: r.fetchedAt,
                                            error: r.error))
            } else {
                merged.append(r)
            }
        }
        // 固定顺序：minimax 在上，火山在下
        let order = ["minimax", "volcengine"]
        self.quotas = merged.sorted {
            let a = order.firstIndex(of: $0.id) ?? Int.max
            let b = order.firstIndex(of: $1.id) ?? Int.max
            return a < b
        }
    }
}
