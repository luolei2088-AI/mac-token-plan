import Foundation

/// Thin one-shot JSON-RPC client for the locally installed Codex App Server.
/// Credentials remain inside Codex; this app never sends tokens in RPC payloads or logs.
final class CodexAppServerClient {
    enum ClientError: LocalizedError {
        case cliUnavailable
        case cliLoginRequired
        case requestFailed(String)
        case missingResponse(method: String, receivedIDs: [String])
        case invalidPayload(String)

        var errorDescription: String? {
            switch self {
            case .cliUnavailable: return "未找到可用的 Codex CLI"
            case .cliLoginRequired: return "请先通过 Codex CLI 登录 ChatGPT 订阅以查看账户详情"
            case .requestFailed(let message): return message
            case .missingResponse(let method, let receivedIDs):
                let ids = receivedIDs.isEmpty ? "无响应" : "收到响应：\(receivedIDs.joined(separator: ", "))"
                return "Codex CLI 未返回 \(method) 响应（\(ids)）"
            case .invalidPayload(let detail): return "Codex CLI \(detail)"
            }
        }
    }

    func fetchSnapshot() async throws -> CodexAccountSnapshot {
        let values = try await request([
            ("account/read", ["refreshToken": false] as [String: Any]),
            ("account/rateLimits/read", [:] as [String: Any]),
            ("account/usage/read", [:] as [String: Any]),
        ])
        guard let account = values["account/read"] as? [String: Any],
              let limits = values["account/rateLimits/read"] as? [String: Any] else {
            throw ClientError.invalidPayload("账户或额度响应不是对象")
        }
        let usage: CodexUsageResponse?
        if let rawUsage = values["account/usage/read"],
           let data = try? JSONSerialization.data(withJSONObject: rawUsage) {
            usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } else {
            usage = nil
        }
        let accountData = try JSONSerialization.data(withJSONObject: [
            "email": account["account"].flatMap { ($0 as? [String: Any])?["email"] } ?? NSNull(),
            "planType": account["account"].flatMap { ($0 as? [String: Any])?["planType"] } ?? NSNull(),
            "ordinaryUsageAllowed": limits["ordinaryUsageAllowed"] ?? NSNull(),
            "rateLimitResetCredits": limits["rateLimitResetCredits"] ?? NSNull(),
            "rateLimitsByLimitId": limits["rateLimitsByLimitId"] ?? NSNull(),
            "rateLimits": limits["rateLimits"] ?? NSNull(),
        ])
        let decoded: SnapshotPayload
        do {
            decoded = try JSONDecoder().decode(SnapshotPayload.self, from: accountData)
        } catch {
            throw ClientError.invalidPayload("额度字段解码失败：\(error.localizedDescription)")
        }
        let models: [CodexAvailableModel]
        let modelsError: String?
        do {
            let response = try await request([("model/list", ["includeHidden": false, "limit": 200] as [String: Any])])
            let data = try JSONSerialization.data(withJSONObject: response["model/list"] ?? [:])
            let modelList = try JSONDecoder().decode(CodexModelListResponse.self, from: data)
            models = modelList.data.filter { !$0.hidden }
            modelsError = nil
        } catch {
            models = []
            modelsError = error.localizedDescription
        }
        return CodexAccountSnapshot(email: decoded.email, planType: decoded.planType,
                                    ordinaryUsageAllowed: decoded.ordinaryUsageAllowed,
                                    rateLimitResetCredits: decoded.rateLimitResetCredits,
                                    rateLimitsByLimitId: decoded.rateLimitsByLimitId,
                                    rateLimits: decoded.rateLimits,
                                    usage: usage, models: models, modelsError: modelsError,
                                    fetchedAt: Date())
    }

    func consumeReset(creditID: String?, idempotencyKey: String) async throws -> String {
        var params: [String: Any] = ["idempotencyKey": idempotencyKey]
        if let creditID { params["creditId"] = creditID }
        let values = try await request([("account/rateLimitResetCredit/consume", params)])
        guard let response = values["account/rateLimitResetCredit/consume"] as? [String: Any],
              let outcome = response["outcome"] as? String else {
            throw ClientError.invalidPayload("没有返回重置结果")
        }
        return outcome
    }

    private func request(_ calls: [(String, [String: Any])]) async throws -> [String: Any] {
        guard let credential = CodexCredential.load(), let codexHome = credential.cliHome else {
            throw ClientError.cliLoginRequired
        }
        guard let executable = CLITool.codex.resolve() else { throw ClientError.cliUnavailable }

        let initialize: [String: Any] = [
            "jsonrpc": "2.0", "id": "init", "method": "initialize",
            "params": [
                "clientInfo": ["name": "mac-token-plan", "title": "mac-token-plan", "version": "1"],
                "capabilities": ["experimentalApi": true],
            ],
        ]
        var environment = CLITool.environment(executable: executable)
        environment["CODEX_HOME"] = codexHome.path
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let values = try Self.runSession(executable: executable, environment: environment,
                                                     initialize: initialize, calls: calls)
                    continuation.resume(returning: values)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Keep stdio alive until each RPC response arrives. Sending all calls and immediately closing
    /// stdin can make app-server shut down while its authenticated backend reads are still running.
    private static func runSession(executable: URL, environment: [String: String], initialize: [String: Any],
                                   calls: [(String, [String: Any])]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input.fileHandleForReading
        process.standardOutput = output.fileHandleForWriting
        process.standardError = errors.fileHandleForWriting
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() }
        catch { throw ClientError.requestFailed("无法启动 Codex CLI App Server") }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()

        DispatchQueue.global(qos: .utility).async {
            while !errors.fileHandleForReading.availableData.isEmpty { }
        }
        let deadline = Date().addingTimeInterval(45)
        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        watchdog.schedule(deadline: .now() + 45)
        watchdog.setEventHandler { if process.isRunning { process.terminate() } }
        watchdog.resume()
        defer { watchdog.cancel() }

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        func readResponse(for expectedID: String) throws -> Any {
            var buffer = Data()
            while Date() < deadline {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let responseID = Self.stringID(object["id"]) else { continue }
                    guard responseID == expectedID else { continue }
                    if let error = object["error"] as? [String: Any] {
                        throw ClientError.requestFailed(error["message"] as? String ?? "Codex CLI 请求失败")
                    }
                    guard let result = object["result"] else {
                        throw ClientError.invalidPayload("响应缺少 result 字段")
                    }
                    return result
                }
            }
            throw ClientError.requestFailed("Codex CLI App Server 请求超时或提前关闭")
        }

        do {
            try send(initialize)
            _ = try readResponse(for: "init")
            try send(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
            var values: [String: Any] = [:]
            for (index, call) in calls.enumerated() {
                let id = "request-\(index)"
                try send(["jsonrpc": "2.0", "id": id, "method": call.0, "params": call.1])
                values[call.0] = try readResponse(for: id)
            }
            try? input.fileHandleForWriting.close()
            if exited.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                process.terminate()
            }
            return values
        } catch {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            _ = exited.wait(timeout: .now() + 1)
            throw error
        }
    }

    private static func stringID(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }
}

private struct SnapshotPayload: Decodable {
    let email: String?
    let planType: String?
    let ordinaryUsageAllowed: Bool?
    let rateLimitResetCredits: CodexResetCredits?
    let rateLimitsByLimitId: [String: CodexRateLimit]?
    let rateLimits: CodexRateLimit?
}
