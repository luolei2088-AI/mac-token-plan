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
    /// 同步剔除已不在新列表中的 ProviderQuota，避免 toggle off 后 UI 仍显示旧段。
    func configure(providers: [QuotaProvider]) {
        self.providers = providers
        let validIDs = Set(providers.map { $0.id })
        let filtered = self.quotas.filter { validIDs.contains($0.id) }
        if filtered.count != self.quotas.count {
            self.quotas = filtered
        }
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
    /// 收尾时丢弃已被 configure() 剔除的 ID，防止 in-flight 写回 stale 段。
    private func fetchAll() async {
        let snapshot = providers
        let snapshotIDs = Set(snapshot.map { $0.id })
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
        // 固定顺序：minimax 上、智谱 GLM 中、火山下；并排除已被 configure 剔除的 ID
        let order = ["minimax", "zhipu_glm", "volcengine"]
        let currentIDs = Set(providers.map { $0.id })
        self.quotas = merged.sorted {
            let a = order.firstIndex(of: $0.id) ?? Int.max
            let b = order.firstIndex(of: $1.id) ?? Int.max
            return a < b
        }.filter { snapshotIDs.contains($0.id) && currentIDs.contains($0.id) }
    }
}
