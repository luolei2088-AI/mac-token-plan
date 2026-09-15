import Foundation

/// 优先使用本应用登录，其次已有本地 CLI 登录，最后回退 .env。
struct CodexCredential {
    let accessToken: String
    /// 实际来源，用于在 UI/日志里标注（排查 token 失效问题时有用）
    let source: String

    /// 按优先级查找：应用专属 auth.json > 本地 CLI auth.json > .env。
    /// 每次调用都重新读文件 —— 文件 < 5KB，IO 可忽略；这样 codex CLI 一旦刷新 token，
    /// 下一次 fetchQuota 就能拿到新值，不用重启 app。
    static func load() -> CodexCredential? {
        if let cred = loadFromCodexCLI() {
            return cred
        }
        if let token = EnvConfig.get(EnvConfig.codexAccessToken),
           !token.trimmingCharacters(in: .whitespaces).isEmpty {
            return CodexCredential(accessToken: token, source: ".env (\(EnvConfig.codexAccessToken))")
        }
        return nil
    }

    /// 读取 ~/.codex/auth.json（macOS codex CLI 默认路径），找 `tokens.access_token`。
    /// 同时兼容 ~/.config/codex/auth.json（Linux 风格）。
    /// 跳过 OpenAI Platform API key 登录态（OPENAI_API_KEY 字段非空但 tokens 为空）——
    /// 那种情况下用户没用 ChatGPT 订阅，没有 5h/7d 窗口可查。
    private static func loadFromCodexCLI() -> CodexCredential? {
        let home = NSHomeDirectory()
        let candidates = [
            CLITool.codexHome.appendingPathComponent("auth.json").path,
            "\(home)/.codex/auth.json",
            "\(home)/.config/codex/auth.json",
        ]
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let tokens = json["tokens"] as? [String: Any],
               let access = tokens["access_token"] as? String,
               !access.isEmpty {
                return CodexCredential(accessToken: access, source: path.hasPrefix(CLITool.codexHome.path) ? "本应用 CLI 登录" : "本地 Codex 登录")
            }
            // auth.json 存在但无 tokens（API key 登录态 / 未完成登录）→ 不发声，仅跳过。
        }
        return nil
    }
}
