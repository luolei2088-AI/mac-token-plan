import Foundation
import CryptoKit

struct CLIRelease {
    let version: String
    let url: URL
    let digest: String
    let inner: String

    static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
        value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    static func parse(_ data: Data, arm: Bool) throws -> CLIRelease {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.message("安装清单格式无效")
        }
        let member = "codex-\(arm ? "aarch64" : "x86_64")-apple-darwin"
        guard let version = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == member + ".tar.gz" }),
              let address = asset["browser_download_url"] as? String,
              let hash = asset["digest"] as? String, hash.hasPrefix("sha256:") else {
            throw CLIError.message("官方清单中缺少 Codex 安装包或 SHA256 校验信息")
        }
        let filename = member + ".tar.gz"
        let inner = member
        let digest = String(hash.dropFirst(7))
        guard safeName(version), safeName(filename), safeName(inner),
              digest.count == 64, digest.allSatisfy({ $0.isHexDigit }),
              let url = URL(string: address), url.scheme == "https",
              url.host == "github.com", url.path.hasPrefix("/openai/codex/releases/download/") else {
            throw CLIError.message("安装清单包含无效路径或校验信息")
        }
        return CLIRelease(version: version, url: url, digest: digest.lowercased(), inner: inner)
    }
}

enum CLIInstaller {
    static func install(progress: @escaping @Sendable (String) async -> Void) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await performInstall(progress: progress) }
            group.addTask {
                try await Task.sleep(nanoseconds: 300_000_000_000)
                throw CLIError.message("安装超时，请检查网络后重试")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private static func performInstall(progress: @escaping @Sendable (String) async -> Void) async throws -> URL {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        await progress("正在获取官方版本…")
        let manifest = "https://api.github.com/repos/openai/codex/releases/latest"
        let (data, response) = try await session.data(from: URL(string: manifest)!)
        try check(response)
        var nativeArm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &nativeArm, &size, nil, 0)
        let release = try CLIRelease.parse(data, arm: nativeArm == 1)
        await progress("正在下载 \(release.version)…")
        let (download, archiveResponse) = try await session.download(from: release.url)
        try check(archiveResponse)
        try Task.checkCancellation()
        await progress("正在校验安装包…")
        let archive = try Data(contentsOf: download, options: .mappedIfSafe)
        let actual = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        try verifyDigest(actual: actual, expected: release.digest)
        let fm = FileManager.default
        // Unique staging folder: a failed attempt can never replace an existing CLI.
        let staging = CLITool.root.appendingPathComponent("cli/codex/.staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        // Only this installation's newly created staging directory is removed.
        defer { try? fm.removeItem(at: staging) }
        let archiveURL = staging.appendingPathComponent("package.tar.gz")
        try fm.moveItem(at: download, to: archiveURL)
        let utility = URL(fileURLWithPath: "/usr/bin/tar")
        let env = CLITool.environment(executable: utility)
        // Inspect archive entries before extracting the single expected root member.
        let listing = try await CLIProcess().run(utility,
            arguments: ["-tzf", archiveURL.path], environment: env)
        let entries = String(decoding: listing.output, as: UTF8.self).split(separator: "\n").map(String.init)
        guard listing.status == 0, validEntries(entries, member: release.inner) else {
            throw CLIError.message("安装包目录结构无效")
        }
        await progress("正在安装并验证 CLI…")
        let binary = staging.appendingPathComponent(release.inner)
        // Stream only the selected member into a file we own. Never let archive
        // metadata create filesystem paths, symlinks, permissions or extra files.
        try Data().write(to: binary)
        let result = try await CLIProcess().run(utility,
            arguments: ["-xOzf", archiveURL.path, release.inner], environment: env, outputFile: binary)
        let values = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard result.status == 0, values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CLIError.message("无法解压 CLI 可执行文件")
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let probe = try await CLIProcess().run(binary, arguments: ["--version"], environment: CLITool.environment(executable: binary))
        guard probe.status == 0, !probe.output.isEmpty else { throw CLIError.message("CLI 安装后无法运行") }
        try Task.checkCancellation()
        let destination = CLITool.root.appendingPathComponent("cli/codex/\(release.version)-\(UUID().uuidString.prefix(8))")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let installed = destination.appendingPathComponent("codex")
        try fm.moveItem(at: binary, to: installed)
        return installed
    }

    static func verifyDigest(actual: String, expected: String) throws {
        guard actual == expected else { throw CLIError.message("安装包校验失败，请重试") }
    }

    static func validEntries(_ entries: [String], member: String) -> Bool {
        entries.filter { $0 == member }.count == 1 && entries.allSatisfy {
            !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..")
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CLIError.message("下载安装资源失败，请检查网络后重试") }
    }
}
