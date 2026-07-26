import AppKit
import SwiftUI
import Combine

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
    private var menuBarController: MenuBarController?
    private let store = QuotaStore()
    private let settings = AppSettings()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.configure(providers: buildProviders())
        store.setRefreshInterval(settings.refreshInterval)

        let card = WidgetCard(store: store, settings: settings) { [weak self] in
            self?.openSettings()
        }
        let panel = DesktopPanel(contentView: card)
        panel.delegate = self
        panel.applyLevel(settings.windowLevel)
        panel.applyMovable(settings.lockPosition)
        panel.show()
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
                   settings.$enabledCodex)
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
