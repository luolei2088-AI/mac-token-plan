import AppKit
import SwiftUI
import Combine
import os.log

@main
enum AppMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // 不显示 Dock 图标
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: DesktopPanel?
    private var settingsWindow: NSWindow?
    private var statisticsWindow: NSWindow?
    private var menuBarController: MenuBarController?
    private let settings = AppSettings()
    // lazy：属性初始化器不能引用实例属性 settings，首次访问（applicationDidFinishLaunching）时才构建
    private lazy var store = QuotaStore(settings: settings)
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.configure(providers: buildProviders())
        store.setRefreshInterval(settings.refreshInterval)

        let card = WidgetCard(store: store, settings: settings, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onOpenStatistics: { [weak self] in self?.openStatistics() })
        let panel = DesktopPanel(contentView: card)
        panel.delegate = self
        panel.applyLevel(settings.windowLevel)
        panel.applyMovable(settings.lockPosition)
        panel.show()
        panel.fitHeightToContent()
        self.panel = panel
        store.start()

        if settings.launchAtLogin { LaunchAtLoginHelper.set(true) }
        bindSettings()

        menuBarController = MenuBarController(
            store: store,
            settings: settings,
            actions: MenuBarController.MenuActions(
                refresh: { [weak self] in self?.store.refresh() },
                openSettings: { [weak self] in self?.openSettings() },
                quit: { NSApp.terminate(nil) }
            )
        )
    }

    // MARK: - 设置即时生效
    private func bindSettings() {
        // 内容行数变化（平台开关、失败降级）后窗口高度自适应；
        // $quotas 在 willSet 发射，receive(on:) 推到下一 runloop 等 SwiftUI 应用新值后再量高。
        store.$quotas
            .receive(on: RunLoop.main)
            .sink { [weak self] qs in
                os_log("quotas changed: %{public}d providers", log: .default, type: .info, qs.count)
                self?.panel?.fitHeightToContent()
            }
            .store(in: &cancellables)
        settings.$refreshInterval
            .sink { [weak self] v in self?.store.setRefreshInterval(v) }
            .store(in: &cancellables)
        settings.$windowLevel
            .sink { [weak self] v in self?.panel?.applyLevel(v) }
            .store(in: &cancellables)
        settings.$lockPosition
            .sink { [weak self] v in self?.panel?.applyMovable(v) }
            .store(in: &cancellables)
        settings.$enabledMinimax
            .merge(with: settings.$enabledZhipuGLM,
                   settings.$enabledVolcengine,
                   settings.$enabledCodex,
                   settings.$enabledDeepSeek)
            // @Published 在 willSet 时发 publisher；sink 内读 self.settings.enabledX 会拿到旧值。
            // 用 receive(on:) 推到下一个 runloop，等 willSet / storage 完成后再读。
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.store.configure(providers: self.buildProviders())
                self.store.refresh()
            }
            .store(in: &cancellables)
    }

    /// 按启用状态 + 已配置凭证构建 Provider。Codex 凭证由 CodexCredential 提供（codex CLI auth.json 优先，回退 .env），其余平台从 .env 读取。
    private func buildProviders() -> [QuotaProvider] {
        var ps: [QuotaProvider] = []
        if settings.enabledMinimax,
           let key = EnvConfig.get(EnvConfig.minimaxApiKey), !key.isEmpty {
            ps.append(MinimaxProvider(apiKey: key))
        }
        if settings.enabledZhipuGLM,
           let key = EnvConfig.get(EnvConfig.zhipuGlmApiKey), !key.isEmpty {
            ps.append(ZhipuGLMProvider(apiKey: key))
        }
        if settings.enabledVolcengine,
           let ak = EnvConfig.get(EnvConfig.volcAk), !ak.isEmpty,
           let sk = EnvConfig.get(EnvConfig.volcSk), !sk.isEmpty {
            ps.append(VolcEngineProvider(ak: ak, sk: sk))
        }
        if settings.enabledCodex {
            ps.append(CodexProvider(credentialLoader: { CodexCredential.load() }))
        }
        if settings.enabledDeepSeek,
           let key = EnvConfig.get(EnvConfig.deepSeekApiKey), !key.isEmpty {
            ps.append(DeepSeekProvider(apiKey: key))
        }
        return ps
    }

    // MARK: - 设置窗口
    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "设置"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: settings) { [weak self] in
                // 保存凭证后重新加载 Provider 并刷新
                self?.store.configure(providers: self?.buildProviders() ?? [])
                self?.store.refresh()
            })
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openStatistics() {
        if statisticsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "使用量统计"
            w.minSize = NSSize(width: 820, height: 560)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: UsageStatisticsView(history: store.usageHistory, settings: settings))
            w.center()
            statisticsWindow = w
        }
        statisticsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 桌面卡片 frame 持久化
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }
    private func saveFrame() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame")
    }
}
