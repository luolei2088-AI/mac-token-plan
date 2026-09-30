import XCTest
@testable import mac_token_plan

final class CLIIntegrationTests: XCTestCase {
    func testCodexManifestRequiresOfficialSourceAndDigest() throws {
        let json = """
        {"tag_name":"rust-v1","assets":[{"name":"codex-aarch64-apple-darwin.tar.gz",
        "browser_download_url":"https://github.com/openai/codex/releases/download/rust-v1/codex-aarch64-apple-darwin.tar.gz",
        "digest":"sha256:\(String(repeating: "b", count: 64))"}]}
        """
        XCTAssertEqual(try CLIRelease.parse(Data(json.utf8), arm: true).inner, "codex-aarch64-apple-darwin")
        XCTAssertThrowsError(try CLIRelease.parse(Data(json.replacingOccurrences(of: "github.com", with: "example.com").utf8), arm: true))
        XCTAssertThrowsError(try CLIRelease.parse(Data(json.utf8), arm: false))
        XCTAssertEqual(try CLIRelease.parse(Data(json.replacingOccurrences(of: "aarch64", with: "x86_64").utf8), arm: false).inner, "codex-x86_64-apple-darwin")
    }

    func testArchiveAndChecksumValidation() throws {
        XCTAssertTrue(CLIInstaller.validEntries(["codex-aarch64-apple-darwin", "README"], member: "codex-aarch64-apple-darwin"))
        XCTAssertFalse(CLIInstaller.validEntries(["codex", "codex"], member: "codex"))
        XCTAssertFalse(CLIInstaller.validEntries(["codex", "../outside"], member: "codex"))
        XCTAssertFalse(CLIInstaller.validEntries(["codex", "/outside"], member: "codex"))
        XCTAssertFalse(CLIInstaller.validEntries(["other"], member: "codex"))
        XCTAssertNoThrow(try CLIInstaller.verifyDigest(actual: "abc", expected: "abc"))
        XCTAssertThrowsError(try CLIInstaller.verifyDigest(actual: "abc", expected: "def"))
    }

    func testOutputFileWithSpaces() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cli-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("binary with spaces")
        try Data().write(to: output)
        let result = try await CLIProcess().run(URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "binary content"], environment: [:], outputFile: output)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.isEmpty)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "binary content")
    }

    func testProcessNonzeroExit() async throws {
        let result = try await CLIProcess().run(URL(fileURLWithPath: "/usr/bin/false"), arguments: [], environment: [:])
        XCTAssertNotEqual(result.status, 0)
    }

    @MainActor
    func testBailianPlatformIsMarkedUnavailable() {
        XCTAssertEqual(AppSettings.allPlatforms.last?.id, "bailian_token_plan")
        XCTAssertEqual(AppSettings.allPlatforms.last?.toggle, \.enabledBailian)
        XCTAssertNotNil(AppSettings.allPlatforms.last?.unavailableReason)
    }

    func testProcessOutputAndArguments() async throws {
        let url = URL(fileURLWithPath: "/usr/bin/printf")
        let result = try await CLIProcess().run(url, arguments: ["%s", "literal $(echo secret) with spaces"], environment: [:])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "literal $(echo secret) with spaces")
    }

    func testProcessTimeout() async {
        let start = Date()
        do {
            _ = try await CLIProcess().run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: [:], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testCancellationBeforeLaunch() async {
        let process = CLIProcess()
        process.cancel()
        do {
            _ = try await process.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: [:])
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationWhileRunning() async {
        let process = CLIProcess()
        let task = Task { try await process.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], environment: [:]) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
