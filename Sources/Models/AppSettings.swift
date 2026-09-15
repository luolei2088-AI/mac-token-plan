import Foundation
import SwiftUI

enum WindowLevelPref: String, CaseIterable {
    case floating, desktop
    var label: String { self == .floating ? "置顶常显" : "贴桌面层" }
}

enum ThemePref: String, CaseIterable {
    case system, light, dark
    var label: String { self == .system ? "跟随系统" : (self == .light ? "浅色" : "深色") }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
}

/// 平台元数据：id 与 QuotaProvider.id / ProviderQuota.id 一致，toggle 指向各自的 enabled 开关。
struct PlatformMeta: Identifiable {
    let id: String
    let name: String
    let toggle: ReferenceWritableKeyPath<AppSettings, Bool>
}

/// 应用配置。非敏感项持久化到 UserDefaults，凭证走 .env（见 EnvConfig）。
@MainActor
final class AppSettings: ObservableObject {
    private let d: UserDefaults

    /// 全部已知平台（UI 列表 + 默认顺序的来源）。
    static let allPlatforms: [PlatformMeta] = [
        PlatformMeta(id: "minimax", name: "MiniMax 月度订阅", toggle: \.enabledMinimax),
        PlatformMeta(id: "zhipu_glm", name: "智谱 GLM Coding Plan", toggle: \.enabledZhipuGLM),
        PlatformMeta(id: "volcengine", name: "火山方舟 Agent Plan", toggle: \.enabledVolcengine),
        PlatformMeta(id: "codex", name: "Codex 订阅", toggle: \.enabledCodex),
        PlatformMeta(id: "deepseek", name: "DeepSeek 开放平台", toggle: \.enabledDeepSeek),
        PlatformMeta(id: "bailian_token_plan", name: "百炼 Token Plan", toggle: \.enabledBailian),
    ]
    static let defaultProviderOrder = allPlatforms.map(\.id)

    @Published var enabledMinimax: Bool { didSet { d.set(enabledMinimax, forKey: "enabled_minimax") } }
    @Published var enabledZhipuGLM: Bool { didSet { d.set(enabledZhipuGLM, forKey: "enabled_zhipu_glm") } }
    @Published var enabledVolcengine: Bool { didSet { d.set(enabledVolcengine, forKey: "enabled_volcengine") } }
    @Published var enabledCodex: Bool { didSet { d.set(enabledCodex, forKey: "enabled_codex") } }
    @Published var enabledDeepSeek: Bool { didSet { d.set(enabledDeepSeek, forKey: "enabled_deepseek") } }
    @Published var enabledBailian: Bool { didSet { d.set(enabledBailian, forKey: "enabled_bailian") } }
    @Published var refreshInterval: Double { didSet { d.set(refreshInterval, forKey: "refresh_interval") } }
    @Published var windowLevel: WindowLevelPref { didSet { d.set(windowLevel.rawValue, forKey: "window_level") } }
    @Published var show5h: Bool { didSet { d.set(show5h, forKey: "show_5h") } }
    @Published var show7d: Bool { didSet { d.set(show7d, forKey: "show_7d") } }
    @Published var showTotal: Bool { didSet { d.set(showTotal, forKey: "show_total") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "opacity") } }
    @Published var cornerRadius: Double { didSet { d.set(cornerRadius, forKey: "corner_radius") } }
    @Published var theme: ThemePref { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launch_at_login") } }
    @Published var lockPosition: Bool { didSet { d.set(lockPosition, forKey: "lock_position") } }
    @Published var showMenuBarScrolling: Bool { didSet { d.set(showMenuBarScrolling, forKey: "show_menu_bar_scrolling") } }
    @Published var providerOrder: [String] { didSet { d.set(providerOrder, forKey: "provider_order") } }

    var enabledProviderIDs: [String] {
        let enabled = Set(Self.allPlatforms.filter { self[keyPath: $0.toggle] }.map(\.id))
        return providerOrder.filter { enabled.contains($0) }
    }

    init(defaults: UserDefaults = .standard) {
        d = defaults
        enabledMinimax = d.object(forKey: "enabled_minimax") as? Bool ?? true
        enabledZhipuGLM = d.object(forKey: "enabled_zhipu_glm") as? Bool ?? false
        enabledVolcengine = d.object(forKey: "enabled_volcengine") as? Bool ?? true
        enabledCodex = d.object(forKey: "enabled_codex") as? Bool ?? false
        enabledDeepSeek = d.object(forKey: "enabled_deepseek") as? Bool ?? false
        enabledBailian = d.object(forKey: "enabled_bailian") as? Bool ?? false
        refreshInterval = d.object(forKey: "refresh_interval") as? Double ?? 300
        windowLevel = WindowLevelPref(rawValue: d.string(forKey: "window_level") ?? "floating") ?? .floating
        show5h = d.object(forKey: "show_5h") as? Bool ?? true
        show7d = d.object(forKey: "show_7d") as? Bool ?? true
        showTotal = d.object(forKey: "show_total") as? Bool ?? true
        opacity = d.object(forKey: "opacity") as? Double ?? 0.92
        cornerRadius = d.object(forKey: "corner_radius") as? Double ?? 16
        theme = ThemePref(rawValue: d.string(forKey: "theme") ?? "system") ?? .system
        launchAtLogin = d.object(forKey: "launch_at_login") as? Bool ?? false
        lockPosition = d.object(forKey: "lock_position") as? Bool ?? false
        showMenuBarScrolling = d.object(forKey: "show_menu_bar_scrolling") as? Bool ?? false
        // 顺序归一化：丢弃未知 id，缺失（新版本新增平台/旧用户无存储）的按默认顺序追加到尾部
        let storedOrder = d.stringArray(forKey: "provider_order") ?? []
        var order = storedOrder.filter { id in Self.allPlatforms.contains { $0.id == id } }
        for p in Self.allPlatforms where !order.contains(p.id) { order.append(p.id) }
        providerOrder = order
    }

    func shouldShow(_ label: String) -> Bool {
        switch label {
        case "5小时": return show5h
        case "7天": return show7d
        case "总额度": return showTotal
        default: return true
        }
    }
}
