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
    private var settingsObservers = Set<AnyCancellable>()
    private var menuActions: MenuActions?

    /// 菜单回调由 AppDelegate 注入，避免 MenuBarController 直接依赖 AppDelegate。
    struct MenuActions {
        var refresh: () -> Void
        var openSettings: () -> Void
        var toggleDesktopCard: () -> Void
        var quit: () -> Void
    }

    init(store: QuotaStore, settings: AppSettings, actions: MenuActions) {
        self.store = store
        self.settings = settings
        self.menuActions = actions
        rebuildSegments()
        bindStore()
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
        settings.$showMenuBarScrolling
            .sink { [weak self] _ in
                self?.updateInstallation()
            }
            .store(in: &settingsObservers)
        settings.$showDesktopCard
            .sink { [weak self] _ in self?.updateInstallation() }
            .store(in: &settingsObservers)
        settings.$quotaDisplayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildSegments() }
            .store(in: &settingsObservers)
    }

    // MARK: - 安装 / 卸载

    private func updateInstallation() {
        if settings.showMenuBarScrolling || !settings.showDesktopCard {
            install()
        } else {
            uninstall()
        }
    }

    private func install() {
        let item: NSStatusItem
        if let current = statusItem {
            item = current
        } else {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
        }
        item.button?.title = currentTitle()
        item.menu = buildMenu()
        if settings.showMenuBarScrolling {
            startSwitchTimer()
        } else {
            switchTimer?.invalidate()
            switchTimer = nil
        }
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
        guard settings.showMenuBarScrolling, !segments.isEmpty else { return }
        currentIndex = (currentIndex + 1) % segments.count
        statusItem?.button?.title = currentTitle()
    }

    // MARK: - 段渲染

    private func rebuildSegments() {
        let newSegments = store.quotas.compactMap { pq -> String? in
            let buckets = pq.buckets.filter { settings.shouldShow($0.label) }
            if settings.quotaDisplayMode == .compact {
                guard let bucket = buckets.first(where: { $0.balanceAmount != nil })
                    ?? buckets.max(by: { $0.percent < $1.percent }) else {
                    return pq.error == nil ? "\(pq.displayName) 暂无可显示额度" : "\(pq.displayName) 获取失败"
                }
                return "\(pq.displayName) \(bucket.compactSummary)"
            }
            if pq.error != nil { return "\(pq.displayName): 获取失败" }
            let parts = buckets.map(\.compactSummary)
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
        guard settings.showMenuBarScrolling else { return "使用量" }
        guard !segments.isEmpty else { return "加载中…" }
        return segments[currentIndex]
    }

    // MARK: - 菜单

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(MenuItemTarget.refresh(_:)), keyEquivalent: "r")
        refresh.target = menuTarget
        menu.addItem(refresh)

        let togglePanel = NSMenuItem(
            title: settings.showDesktopCard ? "隐藏桌面卡片" : "显示桌面卡片",
            action: #selector(MenuItemTarget.toggleDesktopCard(_:)), keyEquivalent: "")
        togglePanel.target = menuTarget
        menu.addItem(togglePanel)

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
        MenuItemTarget(actions: menuActions ?? MenuActions(refresh: {}, openSettings: {}, toggleDesktopCard: {}, quit: {}))
    }()

    @MainActor
    final class MenuItemTarget: NSObject {
        private let actions: MenuActions
        init(actions: MenuActions) { self.actions = actions }

        @objc func refresh(_ sender: Any?) { actions.refresh() }
        @objc func openSettings(_ sender: Any?) { actions.openSettings() }
        @objc func toggleDesktopCard(_ sender: Any?) { actions.toggleDesktopCard() }
        @objc func quit(_ sender: Any?) { actions.quit() }
    }
}
