import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onSaved: () -> Void
    @State private var deepSeekKey = EnvConfig.get(EnvConfig.deepSeekApiKey) ?? ""
    @State private var saved = false
    @State private var dragging: String?

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机自启（登录时启动）", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, v in
                        LaunchAtLoginHelper.set(v)
                    }
            }
            Section("菜单栏") {
                Toggle("在菜单栏中显示", isOn: $settings.showMenuBarScrolling)
            }
            Section("桌面卡片") {
                Toggle("显示桌面卡片", isOn: $settings.showDesktopCard)
                Picker("用量展示", selection: $settings.quotaDisplayMode) {
                    ForEach(QuotaDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                Text("精简模式会缩小卡片，并减少菜单栏中的额度摘要。")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("隐藏桌面卡片时，会保留菜单栏入口以便重新显示。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("平台") {
                Text("拖动行调整桌面卡片的显示顺序。")
                    .font(.caption2).foregroundStyle(.secondary)
                // macOS 上 Form/List 管理的行会吞掉 onDrag/onDrop，改用普通 VStack 承载拖放
                VStack(spacing: 2) {
                    ForEach(settings.providerOrder.filter { $0 == "codex" || $0 == "deepseek" }.compactMap { id in
                        AppSettings.allPlatforms.first { $0.id == id }
                    }) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                Toggle(p.name, isOn: toggleBinding(p))
                                    .disabled(p.unavailableReason != nil)
                                Spacer()
                                if p.unavailableReason != nil {
                                    Text("暂时下线").font(.caption2).foregroundStyle(.secondary)
                                } else if !settings[keyPath: p.toggle] {
                                    Text("未启用").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if let reason = p.unavailableReason {
                                Text(reason).font(.caption2).foregroundStyle(.secondary)
                                    .padding(.leading, 28)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .onDrag {
                            dragging = p.id
                            return NSItemProvider(object: p.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: PlatformDropDelegate(
                            target: p.id,
                            dragging: $dragging,
                            onMove: { movePlatform($0, to: $1) }
                        ))
                    }
                }
                .padding(.vertical, 2)
            }
            Section("API 密钥（存入 .env）") {
                SecureField("DeepSeek API Key", text: $deepSeekKey)
                HStack {
                    Button("保存凭证") { saveCredentials() }
                    if saved { Text("已保存").foregroundStyle(.green).font(.caption) }
                }
            }
            Section("CLI 接入") {
                CLIConnectionView(tool: .codex, onConnected: onSaved)
            }
            Section("刷新") {
                Picker("间隔", selection: $settings.refreshInterval) {
                    Text("1 分钟").tag(60.0)
                    Text("5 分钟").tag(300.0)
                    Text("15 分钟").tag(900.0)
                    Text("30 分钟").tag(1800.0)
                }
            }
            Section("窗口") {
                Toggle("固定位置（禁止拖动）", isOn: $settings.lockPosition)
                Text("关闭固定后可在卡片任意位置拖动，按住四角可调整窗口大小。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("层级", selection: $settings.windowLevel) {
                    ForEach(WindowLevelPref.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("外观") {
                Picker("主题", selection: $settings.theme) {
                    ForEach(ThemePref.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Slider(value: $settings.opacity, in: 0.5...1.0) { Text("不透明度") }
                Slider(value: $settings.cornerRadius, in: 4...28) { Text("圆角") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 600)
    }

    /// 平台开关是独立字段（enabledXxx），拖动列表按 providerOrder 动态驱动，用 keyPath 合成 Binding。
    private func toggleBinding(_ p: PlatformMeta) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: p.toggle] },
            set: { settings[keyPath: p.toggle] = p.unavailableReason == nil ? $0 : false }
        )
    }

    private func movePlatform(_ dragged: String, to target: String) {
        guard dragged != target,
              let from = settings.providerOrder.firstIndex(of: dragged),
              let to = settings.providerOrder.firstIndex(of: target) else { return }
        withAnimation {
            settings.providerOrder.move(fromOffsets: IndexSet(integer: from),
                                        toOffset: to > from ? to + 1 : to)
        }
    }

    private func saveCredentials() {
        EnvConfig.set(EnvConfig.deepSeekApiKey, deepSeekKey)
        saved = true
        onSaved()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}

/// 拖动中经过目标行即实时重排（dropEntered），落点以 .move 语义处理。
private struct PlatformDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let onMove: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged = dragging else { return }
        onMove(dragged, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
