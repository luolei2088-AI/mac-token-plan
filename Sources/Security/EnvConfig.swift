import Foundation

/// 从 .env 读取配置。按以下顺序查找 .env：
/// 1. 当前工作目录 `.env`（`swift run` 在项目根时生效）
/// 2. `~/.config/mac-token-plan/.env`（.app 运行时推荐位置）
/// 3. .app bundle 同目录 `.env`
enum EnvConfig {
    static let minimaxApiKey = "MINIMAX_API_KEY"
    static let volcAk = "VOLC_AK"
    static let volcSk = "VOLC_SK"
    static let zhipuGlmApiKey = "ZHIPU_GLM_API_KEY"
    static let codexAccessToken = "CODEX_ACCESS_TOKEN"
    static let deepSeekApiKey = "DEEPSEEK_API_KEY"

    private static var envURL: URL? {
        let candidates = [
            URL(fileURLWithPath: ".env"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/mac-token-plan/.env"),
            URL(fileURLWithPath: Bundle.main.bundlePath).appendingPathComponent(".env"),
        ]
        // resolvingSymlinksInPath：.env 可能是指向真实配置的软链（单一数据源）。
        // set 的原子写（临时文件+rename）会把软链本身替换掉，必须解析到真实路径再写。
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.resolvingSymlinksInPath()
    }

    static func get(_ key: String) -> String? {
        guard let url = envURL, let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key {
                return String(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    static func set(_ key: String, _ value: String) {
        let url = envURL ?? URL(fileURLWithPath: ".env")
        var lines: [(String, String)] = []
        var found = false
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let k = String(parts[0].trimmingCharacters(in: .whitespaces))
                    let v = String(parts[1].trimmingCharacters(in: .whitespaces))
                    if k == key { lines.append((k, value)); found = true }
                    else { lines.append((k, v)) }
                }
            }
        }
        if !found { lines.append((key, value)) }
        let text = lines.map { "\($0.0)=\($0.1)" }.joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
