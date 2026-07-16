import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onSaved: () -> Void
    @State private var minimaxKey = EnvConfig.get(EnvConfig.minimaxApiKey) ?? ""
    @State private var zhipuGlmKey = EnvConfig.get(EnvConfig.zhipuGlmApiKey) ?? ""
    @State private var volcAk = EnvConfig.get(EnvConfig.volcAk) ?? ""
    @State private var volcSk = EnvConfig.get(EnvConfig.volcSk) ?? ""
    @State private var saved = false

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
            Section("平台") {
                Toggle("MiniMax 月度订阅", isOn: $settings.enabledMinimax)
                Toggle("智谱 GLM Coding Plan", isOn: $settings.enabledZhipuGLM)
                Toggle("火山方舟 Agent Plan", isOn: $settings.enabledVolcengine)
            }
            Section("API 凭证（存入项目 .env）") {
                SecureField("MiniMax API Key", text: $minimaxKey)
                SecureField("智谱 GLM API Key", text: $zhipuGlmKey)
                SecureField("火山 Access Key (AK)", text: $volcAk)
                SecureField("火山 Secret Key (SK)", text: $volcSk)
                HStack {
                    Button("保存凭证") { saveCredentials() }
                    if saved { Text("已保存").foregroundStyle(.green).font(.caption) }
                }
            }
            Section("显示维度") {
                Toggle("5小时额度", isOn: $settings.show5h)
                Toggle("7天额度", isOn: $settings.show7d)
                Toggle("总额度", isOn: $settings.showTotal)
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

    private func saveCredentials() {
        EnvConfig.set(EnvConfig.minimaxApiKey, minimaxKey)
        EnvConfig.set(EnvConfig.zhipuGlmApiKey, zhipuGlmKey)
        EnvConfig.set(EnvConfig.volcAk, volcAk)
        EnvConfig.set(EnvConfig.volcSk, volcSk)
        saved = true
        onSaved()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
