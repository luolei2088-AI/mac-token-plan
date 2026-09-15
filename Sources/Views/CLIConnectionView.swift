import SwiftUI
import AppKit

struct CLIConnectionView: View {
    let tool: CLITool
    var onConnected: () -> Void
    @ObservedObject private var store = CLIConnectionStore.shared
    @State private var customPath = ""

    var body: some View {
        let state = store.status(tool)
        VStack(alignment: .leading, spacing: 8) {
            Text(tool.name).font(.headline)
            Text(state.version).font(.caption).foregroundStyle(.secondary)
            if let path = state.path {
                Text(path.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text(state.connection).font(.caption)
            if let progress = state.progress {
                HStack { ProgressView().controlSize(.small); Text(progress).font(.caption); Button("取消") { store.cancel(tool) } }
            } else {
                HStack {
                    if state.path == nil { Button("安装") { store.install(tool) } }
                    else { Button("登录 / 重新登录") { store.login(tool, onConnected: onConnected) } }
                    Button("检查连接") { store.check(tool, onConnected: onConnected) }
                    Button("检测安装") { store.detect(tool) }
                }.controlSize(.small)
            }
            DisclosureGroup("CLI 路径") {
                TextField("留空自动查找", text: $customPath)
                HStack {
                    Button("选择文件") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { customPath = url.path; savePath() }
                    }
                    Button("应用路径") { savePath() }
                }.disabled(state.progress != nil)
            }.font(.caption)
            Text("安装到本应用管理的用户目录，无需管理员权限。安装完成后点击登录，在浏览器中授权。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .onAppear {
            customPath = UserDefaults.standard.string(forKey: tool.pathKey) ?? ""
            store.detect(tool)
        }
    }

    private func savePath() {
        UserDefaults.standard.set(customPath.trimmingCharacters(in: .whitespacesAndNewlines), forKey: tool.pathKey)
        store.detect(tool)
    }
}
