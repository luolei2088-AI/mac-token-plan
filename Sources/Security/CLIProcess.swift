import Foundation
import Darwin

struct CLIResult {
    let status: Int32
    let output: Data
}

enum CLIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

/// Pipes are drained on separate queues; cancellation also handles launch races.
final class CLIProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if let running, running.isRunning {
            running.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if running.isRunning { kill(running.processIdentifier, SIGKILL) }
            }
        }
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String],
             timeout: TimeInterval = 30, outputFile: URL? = nil, input: Data? = nil) async throws -> CLIResult {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let result = try self.runSync(executable, arguments: arguments,
                                                      environment: environment, timeout: timeout, outputFile: outputFile,
                                                      input: input)
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.cancel() })
    }

    private func runSync(_ executable: URL, arguments: [String], environment: [String: String],
                         timeout: TimeInterval, outputFile: URL?, input: Data?) throws -> CLIResult {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        p.environment = environment
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let stdin = input == nil ? nil : Pipe()
        p.standardInput = stdin?.fileHandleForReading ?? FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        let fileHandle = try outputFile.map { try FileHandle(forWritingTo: $0) }
        defer { try? fileHandle?.close() }
        p.standardOutput = fileHandle ?? out.fileHandleForWriting
        p.standardError = err
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try p.run(); process = p; lock.unlock() }
        catch { lock.unlock(); throw CLIError.message("无法启动 CLI，请检查所选文件及运行依赖") }
        if let input, let stdin {
            do { try stdin.fileHandleForWriting.write(contentsOf: input) } catch { }
            try? stdin.fileHandleForWriting.close()
        }
        // Close our writer copies so readers see EOF after the child exits.
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        let buffers = ProcessBuffers()
        let drains = DispatchGroup()
        let readers = fileHandle == nil ? [(out.fileHandleForReading, true), (err.fileHandleForReading, false)] : [(err.fileHandleForReading, false)]
        for (handle, keep) in readers {
            drains.enter()
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    if keep { buffers.append(data) }
                }
                drains.leave()
            }
        }
        let timedOut = done.wait(timeout: .now() + timeout) == .timedOut
        if timedOut { cancel(); _ = done.wait(timeout: .now() + 3) }
        // Descendants may hold pipe descriptors; never wait indefinitely for EOF.
        _ = drains.wait(timeout: .now() + 2)
        lock.lock()
        let wasCancelled = cancelled
        process = nil
        lock.unlock()
        if timedOut { throw CLIError.message("CLI 操作超时，请重试") }
        if wasCancelled { throw CancellationError() }
        let captured = buffers.snapshot()
        guard !captured.1 else { throw CLIError.message("CLI 输出过大，无法解析") }
        return CLIResult(status: p.terminationStatus, output: captured.0)
    }
}

private final class ProcessBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var overflow = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        if data.count + chunk.count <= 4 * 1024 * 1024 { data.append(chunk) }
        else { overflow = true }
    }
    func snapshot() -> (Data, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (data, overflow)
    }
}
