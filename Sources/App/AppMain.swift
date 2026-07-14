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
        panel.show()
        self.panel = panel
        store.start()

        if settings.launchAtLogin { LaunchAtLoginHelper.set(true) }
        bindSettings()
    }

    // MARK: - 设置即时生效
    private func bindSettings() {
        settings.$refreshInterval
            .sink { [weak self] v in self?.store.setRefreshInterval(v) }
            .store(in: &cancellables)
        settings.$windowLevel
            .sink { [weak self] v in self?.panel?.applyLevel(v) }
            .store(in: &cancellables)
        settings.$enabledMinimax
            .merge(with: settings.$enabledVolcengine)
            .sink { [weak self] _ in
                guard let self else { return }
                self.store.configure(providers: self.buildProviders())
                self.store.refresh()
            }
            .store(in: &cancellables)
    }

    /// 按启用状态 + 已配置凭证构建 Provider。凭证从项目 .env 读取。
    private func buildProviders() -> [QuotaProvider] {
        var ps: [QuotaProvider] = []
        if settings.enabledMinimax,
           let key = EnvConfig.get(EnvConfig.minimaxApiKey), !key.isEmpty {
            ps.append(MinimaxProvider(apiKey: key))
        }
        if settings.enabledVolcengine,
           let ak = EnvConfig.get(EnvConfig.volcAk), !ak.isEmpty,
           let sk = EnvConfig.get(EnvConfig.volcSk), !sk.isEmpty {
            ps.append(VolcEngineProvider(ak: ak, sk: sk))
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
