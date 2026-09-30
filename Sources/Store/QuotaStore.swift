import Foundation
import SwiftUI
import Combine
import os.log

/// 额度数据中枢：持有 Provider 列表，定时刷新、缓存、错误降级。
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var quotas: [ProviderQuota] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var codexAccount: CodexAccountSnapshot?
    @Published private(set) var codexAccountError: String?
    @Published private(set) var isLoadingCodexAccount = false
    @Published private(set) var deepSeekAccount: DeepSeekAccountSnapshot?
    @Published private(set) var deepSeekAccountError: String?
    @Published private(set) var isLoadingDeepSeekAccount = false
    @Published private(set) var isConsumingCodexReset = false
    @Published private(set) var codexResetResult: String?
    let usageHistory: UsageHistoryStore

    private var timer: Timer?
    private var interval: TimeInterval = 300
    private var providers: [QuotaProvider] = []
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var pendingCodexResetKey: String?

    init(settings: AppSettings, usageHistory: UsageHistoryStore? = nil) {
        self.settings = settings
        self.usageHistory = usageHistory ?? UsageHistoryStore()
        // 顺序变化（设置面板拖动）即时重排现有数据，不等下次刷新。
        // $providerOrder 发射的是新值，直接用发射参数排序。
        settings.$providerOrder
            .receive(on: RunLoop.main)
            .sink { [weak self] order in
                guard let self, !self.quotas.isEmpty else { return }
                self.quotas.sort {
                    Self.orderIndex($0.id, in: order) < Self.orderIndex($1.id, in: order)
                }
            }
            .store(in: &cancellables)
    }

    private static func orderIndex(_ id: String, in order: [String]) -> Int {
        order.firstIndex(of: id) ?? Int.max
    }

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
            self.usageHistory.record(self.quotas)
            if self.settings.enabledCodex { await self.fetchCodexAccount() }
        }
    }

    func refreshCodexAccount() {
        guard settings.enabledCodex else { return }
        Task { await fetchCodexAccount() }
    }

    func refreshDeepSeekAccount() {
        guard settings.enabledDeepSeek, !isLoadingDeepSeekAccount,
              let apiKey = EnvConfig.get(EnvConfig.deepSeekApiKey), !apiKey.isEmpty else { return }
        isLoadingDeepSeekAccount = true
        deepSeekAccountError = nil
        Task {
            defer { isLoadingDeepSeekAccount = false }
            do {
                deepSeekAccount = try await DeepSeekProvider(apiKey: apiKey).fetchDetails()
                deepSeekAccountError = nil
            } catch {
                deepSeekAccountError = error.localizedDescription
            }
        }
    }

    private func fetchCodexAccount() async {
        guard !isLoadingCodexAccount else { return }
        isLoadingCodexAccount = true
        defer { isLoadingCodexAccount = false }
        do {
            codexAccount = try await CodexAppServerClient().fetchSnapshot()
            codexAccountError = nil
        } catch {
            codexAccountError = error.localizedDescription
        }
    }

    func consumeCodexReset(creditID: String?) async {
        guard !isConsumingCodexReset else { return }
        isConsumingCodexReset = true
        codexResetResult = nil
        defer { isConsumingCodexReset = false }
        do {
            let idempotencyKey = pendingCodexResetKey ?? UserDefaults.standard.string(forKey: "codex_reset_pending_key") ?? UUID().uuidString
            pendingCodexResetKey = idempotencyKey
            UserDefaults.standard.set(idempotencyKey, forKey: "codex_reset_pending_key")
            let outcome = try await CodexAppServerClient().consumeReset(creditID: creditID, idempotencyKey: idempotencyKey)
            switch outcome {
            case "reset": codexResetResult = "重置成功"
            case "nothingToReset": codexResetResult = "当前没有可重置的额度窗口"
            case "noCredit": codexResetResult = "没有可用的重置卡"
            case "alreadyRedeemed": codexResetResult = "此重置请求已完成"
            default: codexResetResult = "重置结果：\(outcome)"
            }
            pendingCodexResetKey = nil
            UserDefaults.standard.removeObject(forKey: "codex_reset_pending_key")
            await fetchCodexAccount()
            refresh()
        } catch {
            codexResetResult = error.localizedDescription
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
                        os_log("fetch %{public}@ failed: %{public}@", log: .default, type: .error, p.id, error.localizedDescription)
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
        // 按 settings.providerOrder 排序（设置面板拖动配置）；并排除已被 configure 剔除的 ID
        let order = settings.providerOrder
        let currentIDs = Set(providers.map { $0.id })
        self.quotas = merged.sorted {
            Self.orderIndex($0.id, in: order) < Self.orderIndex($1.id, in: order)
        }.filter { snapshotIDs.contains($0.id) && currentIDs.contains($0.id) }
    }
}
