import AppKit
import Combine

/// 菜单栏（NSStatusBar）滚动显示额度数据。
/// 切换式：每个 provider 渲染成一段文本，定时器每隔 N 秒切换到下一段，循环。
/// 数据来自 QuotaStore（订阅 objectWillChange 自动跟随刷新），无需自己触发网络请求。
@MainActor
final class MenuBarController {
    private let store: QuotaStore
    private let settings: AppSettings

    private var statusItem: NSStatusItem?
    private var segments: [String] = []
    private var currentIndex: Int = 0
    private var switchTimer: Timer?
    private let switchInterval: TimeInterval = 5

    private var storeObserver: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    private var menuActions: MenuActions?

    /// 菜单回调由 AppDelegate 注入，避免 MenuBarController 直接依赖 AppDelegate。
    struct MenuActions {
        var refresh: () -> Void
        var openSettings: () -> Void
        var quit: () -> Void
    }

    init(store: QuotaStore, settings: AppSettings, actions: MenuActions) {
        self.store = store
        self.settings = settings
        self.menuActions = actions
        rebuildSegments()
        bindStore()
        if settings.showMenuBarScrolling { install() }
        bindSettings()
    }

    deinit {
        switchTimer?.invalidate()
    }

    // MARK: - 订阅

    private func bindStore() {
        storeObserver = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange 在赋值前触发，下一 runloop 读 quotas 已是新值
                DispatchQueue.main.async { self?.rebuildSegments() }
            }
    }

    private func bindSettings() {
        settingsObserver = settings.$showMenuBarScrolling
            .sink { [weak self] enabled in
                if enabled { self?.install() } else { self?.uninstall() }
            }
    }

    // MARK: - 安装 / 卸载

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = currentTitle()
        item.menu = buildMenu()
        statusItem = item
        startSwitchTimer()
    }

    private func uninstall() {
        switchTimer?.invalidate()
        switchTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - 切换定时器

    private func startSwitchTimer() {
        switchTimer?.invalidate()
        switchTimer = Timer.scheduledTimer(withTimeInterval: switchInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }

    private func advance() {
        guard !segments.isEmpty else { return }
        currentIndex = (currentIndex + 1) % segments.count
        statusItem?.button?.title = currentTitle()
    }

    // MARK: - 段渲染

    private func rebuildSegments() {
        let newSegments = store.quotas.compactMap { pq -> String? in
            if pq.error != nil { return "\(pq.displayName): 获取失败" }
            let parts = pq.buckets
                .filter { settings.shouldShow($0.label) }
                .map { bucket -> String in
                    if let amount = bucket.balanceAmount {
                        // 金额维度（余额类）：显示金额而非百分比
                        return "\(segmentLabel(bucket)):\(bucket.currencySymbol)\(String(format: "%.2f", amount))"
                    }
                    let pct = Int((bucket.percent * 100).rounded())
                    return "\(segmentLabel(bucket)):\(pct)%"
                }
            if parts.isEmpty { return nil }
            return "\(pq.displayName) " + parts.joined(separator: " ")
        }
        if newSegments.isEmpty {
            segments = ["加载中…"]
        } else {
            segments = newSegments
        }
        if currentIndex >= segments.count { currentIndex = 0 }
        statusItem?.button?.title = currentTitle()
    }

    private func currentTitle() -> String {
        guard !segments.isEmpty else { return "加载中…" }
        return segments[currentIndex]
    }

    /// 段内维度短标签；有来源标注（Codex 账户/模型额度池）时加前缀区分。
    private func segmentLabel(_ bucket: QuotaBucket) -> String {
        let short = shortLabel(bucket.label)
        if let s = bucket.source, !s.isEmpty { return "\(s)·\(short)" }
        return short
    }

    private func shortLabel(_ label: String) -> String {
        switch label {
        case "5小时": return "5h"
        case "7天":   return "7d"
        case "总额度": return "总"
        default:      return label
        }
    }

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(MenuItemTarget.refresh(_:)), keyEquivalent: "r")
        refresh.target = menuTarget
        menu.addItem(refresh)

        let openSettings = NSMenuItem(title: "打开设置…", action: #selector(MenuItemTarget.openSettings(_:)), keyEquivalent: ",")
        openSettings.target = menuTarget
        menu.addItem(openSettings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(MenuItemTarget.quit(_:)), keyEquivalent: "q")
        quit.target = menuTarget
        menu.addItem(quit)

        return menu
    }

    /// 持有 NSMenuItem target 的小对象，回调通过闭包转发到 MenuActions。
    private lazy var menuTarget: MenuItemTarget = {
        MenuItemTarget(actions: menuActions ?? MenuActions(refresh: {}, openSettings: {}, quit: {}))
    }()

    @MainActor
    final class MenuItemTarget: NSObject {
        private let actions: MenuActions
        init(actions: MenuActions) { self.actions = actions }

        @objc func refresh(_ sender: Any?) { actions.refresh() }
        @objc func openSettings(_ sender: Any?) { actions.openSettings() }
        @objc func quit(_ sender: Any?) { actions.quit() }
    }
}