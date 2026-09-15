import XCTest
@testable import mac_token_plan

final class CLIIntegrationTests: XCTestCase {
    func testBailianWindowsAndMilliseconds() throws {
        let buckets = try BailianTokenPlanProvider.parse(Data(#"{"per5HourPercentage":0,"per5HourResetTime":1787001180000,"per1WeekPercentage":0.7}"#.utf8))
        XCTAssertEqual(buckets.map(\.label), ["5小时", "7天"])
        XCTAssertEqual(buckets[0].used, 0)
        XCTAssertEqual(buckets[1].used, 70)
        XCTAssertEqual(buckets[0].resetTime?.timeIntervalSince1970, 1787001180)
        XCTAssertNil(buckets[1].resetTime)
    }

    func testWeeklyOnlyAndOverLimit() throws {
        let buckets = try BailianTokenPlanProvider.parse(Data(#"{"per1WeekPercentage":1.2}"#.utf8))
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].label, "7天")
        XCTAssertEqual(buckets[0].used, 120)
        XCTAssertEqual(buckets[0].percent, 1)
    }

    func testInvalidResponseIsNotZeroUsage() {
        for json in ["{}", "not json", #"{"per1WeekPercentage":-1}"#, #"{"per1WeekPercentage":"bad"}"#] {
            XCTAssertThrowsError(try BailianTokenPlanProvider.parse(Data(json.utf8)))
        }
    }

    func testMissingCLI() async {
        do {
            _ = try await BailianTokenPlanProvider(executable: { nil }).fetchQuota()
            XCTFail("Missing CLI must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("未找到")) }
    }

    func testBailianCommandAndFailure() async throws {
        let url = URL(fileURLWithPath: "/test path/bl")
        let provider = BailianTokenPlanProvider(executable: { url }) { executable, args, env in
            XCTAssertEqual(executable, url)
            XCTAssertEqual(args, BailianTokenPlanProvider.arguments)
            XCTAssertNil(env["OPENAI_API_KEY"])
            return CLIResult(status: 0, output: Data(#"{"per1WeekPercentage":0.2}"#.utf8))
        }
        let buckets = try await provider.fetchQuota()
        XCTAssertEqual(buckets.first?.used, 20)
        let failed = BailianTokenPlanProvider(executable: { url }) { _, _, _ in
            CLIResult(status: 1, output: Data("secret-value".utf8))
        }
        do { _ = try await failed.fetchQuota(); XCTFail("Nonzero exit must fail") }
        catch { XCTAssertFalse(error.localizedDescription.contains("secret-value")) }
    }

    func testManifestArchitectureAndValidation() throws {
        let hash = String(repeating: "a", count: 64)
        let json = """
        {"version":"1.24.0","assets":{
        "darwin-arm64":{"file":"arm.zip","inner":"bl-arm","sha256":"\(hash)"},
        "darwin-x64":{"file":"intel.zip","inner":"bl-intel","sha256":"\(hash)"}}}
        """
        XCTAssertEqual(try CLIRelease.parse(Data(json.utf8), tool: .bailian, arm: true).inner, "bl-arm")
        XCTAssertEqual(try CLIRelease.parse(Data(json.utf8), tool: .bailian, arm: false).inner, "bl-intel")
        XCTAssertThrowsError(try CLIRelease.parse(Data(json.replacingOccurrences(of: "arm.zip", with: "../arm.zip").utf8), tool: .bailian, arm: true))
        XCTAssertFalse(CLIRelease.safeName(".."))
    }

    func testCodexManifestRequiresOfficialSourceAndDigest() throws {
        let json = """
        {"tag_name":"rust-v1","assets":[{"name":"codex-aarch64-apple-darwin.tar.gz",
        "browser_download_url":"https://github.com/openai/codex/releases/download/rust-v1/codex-aarch64-apple-darwin.tar.gz",
        "digest":"sha256:\(String(repeating: "b", count: 64))"}]}
        """
        XCTAssertFalse(try CLIRelease.parse(Data(json.utf8), tool: .codex, arm: true).zip)
        XCTAssertThrowsError(try CLIRelease.parse(Data(json.replacingOccurrences(of: "github.com", with: "example.com").utf8), tool: .codex, arm: true))
        XCTAssertThrowsError(try CLIRelease.parse(Data(json.utf8), tool: .codex, arm: false))
        XCTAssertEqual(try CLIRelease.parse(Data(json.replacingOccurrences(of: "aarch64", with: "x86_64").utf8), tool: .codex, arm: false).inner, "codex-x86_64-apple-darwin")
    }

    func testArchiveAndChecksumValidation() throws {
        XCTAssertTrue(CLIInstaller.validEntries(["bl", "README"], member: "bl"))
        XCTAssertFalse(CLIInstaller.validEntries(["bl", "bl"], member: "bl"))
        XCTAssertFalse(CLIInstaller.validEntries(["bl", "../outside"], member: "bl"))
        XCTAssertFalse(CLIInstaller.validEntries(["bl", "/outside"], member: "bl"))
        XCTAssertFalse(CLIInstaller.validEntries(["other"], member: "bl"))
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
    func testBailianPlatformRegistration() {
        XCTAssertEqual(AppSettings.allPlatforms.last?.id, "bailian_token_plan")
        XCTAssertEqual(AppSettings.allPlatforms.last?.toggle, \.enabledBailian)
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
