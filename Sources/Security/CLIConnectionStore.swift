import Foundation
import SwiftUI

struct CLIStatus {
    var path: URL?
    var version = "未检测"
    var connection = "未检查连接"
    var progress: String?
}

@MainActor
final class CLIConnectionStore: ObservableObject {
    @Published var states: [CLITool: CLIStatus] = [:]
    private var tasks: [CLITool: Task<Void, Never>] = [:]
    static let shared = CLIConnectionStore()

    func status(_ tool: CLITool) -> CLIStatus { states[tool] ?? CLIStatus() }
    func cancel(_ tool: CLITool) { tasks[tool]?.cancel() }

    private func start(_ tool: CLITool, operation: @escaping () async throws -> Void) {
        guard tasks[tool] == nil else { return }
        tasks[tool] = Task {
            defer { states[tool, default: CLIStatus()].progress = nil; tasks[tool] = nil }
            do { try await operation() }
            catch is CancellationError { states[tool, default: CLIStatus()].connection = "操作已取消" }
            catch {
                // Do not surface CLI stdout/stderr, URLs containing auth codes, or credentials.
                states[tool, default: CLIStatus()].connection = (error as? CLIError)?.localizedDescription ?? "操作失败，请检查网络或 CLI 配置后重试"
            }
        }
    }

    func detect(_ tool: CLITool) {
        start(tool) { [self] in try await detectNow(tool) }
    }

    private func detectNow(_ tool: CLITool) async throws {
        let url = tool.resolve()
        if states[tool]?.path != url { states[tool, default: CLIStatus()].connection = "未检查连接" }
        states[tool, default: CLIStatus()].path = url
        guard let url else { states[tool, default: CLIStatus()].version = "未安装或路径无效"; return }
        states[tool, default: CLIStatus()].progress = "正在检测…"
        let result = try await CLIProcess().run(url, arguments: ["--version"], environment: CLITool.environment(executable: url))
        guard result.status == 0 else { throw CLIError.message("CLI 无法运行，请检查路径及运行依赖") }
        states[tool, default: CLIStatus()].version = String(String(decoding: result.output, as: UTF8.self).prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func install(_ tool: CLITool) {
        start(tool) { [self] in
            states[tool, default: CLIStatus()].progress = "准备安装…"
            let url = try await CLIInstaller.install { message in
                await MainActor.run { self.states[tool, default: CLIStatus()].progress = message }
            }
            try Task.checkCancellation()
            UserDefaults.standard.set(url.path, forKey: tool.installedKey)
            UserDefaults.standard.set("", forKey: tool.pathKey)
            try await detectNow(tool)
            states[tool, default: CLIStatus()].connection = "安装完成，请点击登录"
        }
    }

    func login(_ tool: CLITool, onConnected: @escaping () -> Void) {
        start(tool) { [self] in
            guard let url = tool.resolve() else { throw CLIError.message("请先安装 CLI") }
            states[tool, default: CLIStatus()].progress = "等待浏览器授权…"
            if tool == .codex {
                try FileManager.default.createDirectory(at: CLITool.codexHome, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
            }
            let args = ["-c", "cli_auth_credentials_store=\"file\"", "login"]
            let result = try await CLIProcess().run(url, arguments: args,
                environment: CLITool.environment(executable: url, managedCodex: true), timeout: 600)
            guard result.status == 0 else { throw CLIError.message("登录未完成，请重试并在浏览器中完成授权") }
            try await checkNow(tool)
            onConnected()
        }
    }

    func check(_ tool: CLITool, onConnected: @escaping () -> Void) {
        start(tool) { [self] in try await checkNow(tool); onConnected() }
    }

    private func checkNow(_ tool: CLITool) async throws {
        states[tool, default: CLIStatus()].progress = "正在检查订阅连接…"
        guard let credential = CodexCredential.load() else {
            throw CLIError.message("未找到可查询的 ChatGPT 登录凭证，请点击登录；API Key 登录不支持订阅查询")
        }
        do { _ = try await CodexProvider(credentialLoader: { CodexCredential.load() }).fetchQuota() }
        catch { throw CLIError.message("Codex 订阅查询失败，请检查网络、订阅或重新登录") }
        states[tool, default: CLIStatus()].connection = "已连接 · \(credential.source)"
    }
}
