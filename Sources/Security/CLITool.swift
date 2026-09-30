import Foundation

enum CLITool: String, CaseIterable, Identifiable {
    case codex
    var id: String { rawValue }
    var command: String { "codex" }
    var name: String { "Codex CLI（ChatGPT 订阅）" }
    var pathKey: String { "cli_path_\(rawValue)" }
    var installedKey: String { "cli_installed_\(rawValue)" }
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mac-token-plan")
    }
    static var codexHome: URL { root.appendingPathComponent("auth/codex") }

    func resolve(defaults: UserDefaults = .standard) -> URL? {
        if let custom = defaults.string(forKey: pathKey), !custom.isEmpty {
            return FileManager.default.isExecutableFile(atPath: custom) ? URL(fileURLWithPath: custom) : nil
        }
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        for directory in directories where directory.hasPrefix("/") {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        if let path = defaults.string(forKey: installedKey), FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func environment(executable: URL, managedCodex: Bool = false) -> [String: String] {
        let original = ProcessInfo.processInfo.environment
        let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "TZ", "XDG_CONFIG_HOME",
                       "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy",
                       "all_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR"]
        var env = original.filter { allowed.contains($0.key) }
        env["HOME"] = NSHomeDirectory()
        env["PATH"] = ([executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            + (original["PATH"] ?? "").split(separator: ":").map(String.init)).joined(separator: ":")
        if managedCodex { env["CODEX_HOME"] = codexHome.path }
        return env
    }
}
