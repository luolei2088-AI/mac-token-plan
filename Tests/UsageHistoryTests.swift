import XCTest
import SwiftUI
import AppKit
@testable import mac_token_plan

final class UsageHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private let now = Date(timeIntervalSince1970: 1_789_459_200)

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("usage-test-\(UUID().uuidString)").appendingPathComponent("history.json")
    }
    private func quota(_ used: Double, reset: Date? = nil, error: String? = nil) -> ProviderQuota {
        ProviderQuota(id: "codex", displayName: "Codex", buckets: [
            QuotaBucket(label: "5小时", used: used, limit: 100, resetTime: reset, source: "Spark")
        ], fetchedAt: now, error: error)
    }

    @MainActor func testBaselineFailureZeroAndRestart() {
        let url = temporaryURL()
        let store = UsageHistoryStore(fileURL: url, calendar: calendar)
        store.record([quota(40)], at: now.addingTimeInterval(-900))
        XCTAssertTrue(store.samples.isEmpty)
        store.record([quota(50, error: "offline")], at: now.addingTimeInterval(-600))
        XCTAssertTrue(store.samples.isEmpty)
        store.record([quota(47)], at: now.addingTimeInterval(-300))
        store.record([quota(47)], at: now)
        XCTAssertEqual(store.samples.map(\.percent), [7, 0])
        let restarted = UsageHistoryStore(fileURL: url, calendar: calendar)
        restarted.record([quota(60)], at: now.addingTimeInterval(300))
        XCTAssertEqual(restarted.samples.map(\.percent), [7, 0])
    }

    @MainActor func testResetWithLowerAndHigherObservedUsage() {
        let store = UsageHistoryStore(fileURL: temporaryURL(), calendar: calendar)
        store.record([quota(80)], at: now.addingTimeInterval(-900))
        store.record([quota(5, reset: now.addingTimeInterval(-100))], at: now.addingTimeInterval(-600))
        store.record([quota(20, reset: now.addingTimeInterval(18000))], at: now)
        XCTAssertEqual(store.samples.map(\.percent), [5, 20])
        // A repeated or out-of-order observation must not create another increment.
        store.record([quota(30)], at: now)
        XCTAssertEqual(store.samples.count, 2)
    }

    private func balance(_ amount: Double, currency: String = "CNY", error: String? = nil) -> ProviderQuota {
        ProviderQuota(id: "deepseek", displayName: "DeepSeek", buckets: [
            QuotaBucket(label: "余额", used: 0, limit: 0, balanceAmount: amount, currency: currency)
        ], fetchedAt: now, error: error)
    }

    @MainActor func testBalanceConsumptionTopUpFailureAndRestart() throws {
        let url = temporaryURL()
        let store = UsageHistoryStore(fileURL: url, calendar: calendar)
        store.record([balance(100)], at: now.addingTimeInterval(-1800))
        XCTAssertTrue(store.samples.isEmpty, "Initial balance is not an expense")
        store.record([balance(99.9999)], at: now.addingTimeInterval(-1500))
        store.record([balance(99.9999)], at: now.addingTimeInterval(-1200))
        store.record([balance(150)], at: now.addingTimeInterval(-900))
        store.record([balance(145, error: "offline")], at: now.addingTimeInterval(-600))
        store.record([balance(148)], at: now.addingTimeInterval(-300))
        store.record([balance(140)], at: now.addingTimeInterval(-300))
        XCTAssertEqual(store.samples.compactMap(\.amount), [0.0001, 0, 0, 2])
        XCTAssertTrue(store.samples.allSatisfy { $0.currency == "CNY" && $0.percent == 0 })
        let restarted = UsageHistoryStore(fileURL: url, calendar: calendar)
        restarted.record([balance(120)], at: now)
        XCTAssertEqual(restarted.samples.compactMap(\.amount), [0.0001, 0, 0, 2])
        let total = restarted.points(period: .oneDay, now: now).reduce(0) { $0 + $1.value }
        XCTAssertEqual(total, 2.0001, accuracy: 0.0000001)
        XCTAssertEqual(restarted.points(period: .oneDay, now: now).first?.series.metric, .money("CNY"))
    }

    @MainActor func testCurrenciesUseIndependentBaselinesAndIdentity() {
        let store = UsageHistoryStore(fileURL: temporaryURL(), calendar: calendar)
        store.record([balance(100), balance(20, currency: "USD")], at: now.addingTimeInterval(-300))
        store.record([balance(99), balance(19.5, currency: "USD"), quota(10)], at: now)
        let points = store.points(period: .oneDay, now: now)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(Set(points.map(\.id)).count, 2)
        XCTAssertEqual(points.first { $0.currency == "CNY" }?.value, 1)
        XCTAssertEqual(points.first { $0.currency == "USD" }?.value, 0.5)
        store.record([balance(.nan)], at: now.addingTimeInterval(300))
        XCTAssertEqual(store.samples.count, 2)
    }

    @MainActor func testMoneyPeriodsAndQuotaRemainSeparate() throws {
        let url = temporaryURL()
        let samples = [0, 3, 20].map { day in
            UsageSample(providerID: "deepseek", source: nil, label: "余额",
                timestamp: now.addingTimeInterval(-Double(day) * 86400 - 600), percent: 0, amount: 1.25, currency: "CNY")
        } + [UsageSample(providerID: "codex", source: nil, label: "7天", timestamp: now, percent: 30)]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(samples).write(to: url)
        let store = UsageHistoryStore(fileURL: url, calendar: calendar)
        for (period, total) in [(UsagePeriod.oneDay, 1.25), (.sevenDays, 2.5), (.thirtyDays, 3.75)] {
            let points = store.points(period: period, now: now)
            XCTAssertEqual(points.filter { $0.series.metric == .money("CNY") }.reduce(0) { $0 + $1.value }, total)
            XCTAssertEqual(points.first { $0.series.metric == .quota }?.value, 30)
        }
    }

    @MainActor func testEnabledChannelsFollowSettingsAndOrder() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "usage-tests-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        for platform in AppSettings.allPlatforms { settings[keyPath: platform.toggle] = false }
        XCTAssertTrue(settings.enabledProviderIDs.isEmpty)
        settings.enabledCodex = true
        settings.enabledDeepSeek = true
        settings.providerOrder = ["deepseek", "codex"] + AppSettings.defaultProviderOrder.filter { $0 != "deepseek" && $0 != "codex" }
        XCTAssertEqual(settings.enabledProviderIDs, ["deepseek", "codex"])
        settings.enabledCodex = false
        XCTAssertEqual(settings.enabledProviderIDs, ["deepseek"])
        XCTAssertEqual(AppSettings(defaults: defaults).enabledProviderIDs, ["deepseek"])
    }

    @MainActor func testAggregationIdentityFiltersAndLegacyCompatibility() throws {
        let url = temporaryURL()
        let date = now.addingTimeInterval(-600)
        let samples = [
            UsageSample(providerID: "codex", source: "Spark", label: "5小时", timestamp: date, percent: 80),
            UsageSample(providerID: "codex", source: "Spark", label: "5小时", timestamp: date.addingTimeInterval(1), percent: 70),
            UsageSample(providerID: "codex", source: "账户", label: "7天", timestamp: date, percent: 4),
            UsageSample(providerID: "volcengine", source: nil, label: "5小时", timestamp: date, percent: 0),
            UsageSample(providerID: "deepseek", source: nil, label: "余额", timestamp: date, percent: 0),
            UsageSample(providerID: "codex", source: "Spark", label: "5小时", timestamp: now.addingTimeInterval(1), percent: 9),
            UsageSample(providerID: "codex", source: "Spark", label: "5小时", timestamp: now.addingTimeInterval(-40 * 86400), percent: 9)
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(samples).write(to: url)
        let store = UsageHistoryStore(fileURL: url, calendar: calendar)
        let points = store.points(period: .oneDay, now: now)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(Set(points.map(\.id)).count, 3)
        XCTAssertEqual(points.first { $0.source == "Spark" }?.percent, 150)
        XCTAssertEqual(points.first { $0.providerID == "volcengine" }?.percent, 0)
        XCTAssertEqual(store.points(period: .oneDay, providerID: "codex", label: "5小时", now: now).map(\.percent), [150])
        XCTAssertEqual(store.samples.count, samples.count, "Legacy records must remain intact")
    }

    func testLocalMidnightAndDSTBuckets() {
        let midnight = calendar.startOfDay(for: now)
        XCTAssertNotEqual(UsagePeriod.sevenDays.bucketStart(midnight.addingTimeInterval(-1), calendar: calendar),
                          UsagePeriod.sevenDays.bucketStart(midnight, calendar: calendar))
        var pacific = calendar
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let daylightChange = pacific.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let end = UsagePeriod.sevenDays.bucketEnd(daylightChange, calendar: pacific)
        XCTAssertEqual(end.timeIntervalSince(daylightChange), 25 * 3600)
        XCTAssertEqual(UsagePeriod.thirtyDays.range(endingAt: now, calendar: calendar).upperBound, now)
    }

    /// Opt-in visual fixture; never reads credentials or writes application history/settings.
    @MainActor func testStatisticsVisualFixture() throws {
        guard let output = ProcessInfo.processInfo.environment["USAGE_SNAPSHOT_DIR"] else { return }
        let url = temporaryURL()
        let providers = ["volcengine", "codex", "bailian_token_plan"]
        var samples: [UsageSample] = []
        for day in 0..<7 {
            for (index, provider) in providers.enumerated() {
                for label in ["5小时", "7天"] {
                    samples.append(UsageSample(providerID: provider, source: provider == "codex" ? "Spark" : nil,
                        label: label, timestamp: Date().addingTimeInterval(-Double(day) * 86400 - 600),
                        percent: Double((day + index + 1) * (label == "5小时" ? 3 : 1))))
                }
            }
        }
        for day in 0..<7 {
            samples.append(UsageSample(providerID: "deepseek", source: nil, label: "余额",
                timestamp: Date().addingTimeInterval(-Double(day) * 86400 - 600), percent: 0,
                amount: Double(day + 1) * 0.013456, currency: "CNY"))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(samples).write(to: url)
        let store = UsageHistoryStore(fileURL: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "usage-visual-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        for platform in AppSettings.allPlatforms { settings[keyPath: platform.toggle] = false }
        settings.enabledVolcengine = true
        settings.enabledCodex = true
        settings.enabledDeepSeek = true
        _ = NSApplication.shared
        let zeroURL = temporaryURL()
        try FileManager.default.createDirectory(at: zeroURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(samples.map {
            UsageSample(providerID: $0.providerID, source: $0.source, label: $0.label, timestamp: $0.timestamp, percent: 0, amount: $0.amount == nil ? nil : 0, currency: $0.currency)
        }).write(to: zeroURL)
        let zeroStore = UsageHistoryStore(fileURL: zeroURL)
        let emptyStore = UsageHistoryStore(fileURL: temporaryURL())
        let scenarios: [(String, NSAppearance.Name, UsagePeriod, CGFloat, Date?)] = [
            ("empty", .aqua, .sevenDays, 820, nil),
            ("zero", .aqua, .sevenDays, 820, UsagePeriod.sevenDays.bucketStart(Date().addingTimeInterval(-600))),
            ("missing-hover", .aqua, .oneDay, 820, UsagePeriod.oneDay.bucketStart(Date().addingTimeInterval(-7200))),
            ("light", .aqua, .sevenDays, 1000, nil),
            ("dark", .darkAqua, .sevenDays, 1000, nil),
            ("hourly-hover", .aqua, .oneDay, 820, UsagePeriod.oneDay.bucketStart(Date().addingTimeInterval(-600))),
            ("monthly-hover", .darkAqua, .thirtyDays, 820, UsagePeriod.thirtyDays.bucketStart(Date().addingTimeInterval(-600)))
        ]
        for (name, appearance, period, width, selectedDate) in scenarios {
            let view = NSHostingView(rootView: UsageStatisticsView(history: name == "empty" ? emptyStore : (name == "zero" ? zeroStore : store), settings: settings,
                period: period, hoveredDate: selectedDate))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1350),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = view
            view.frame = NSRect(x: 0, y: 0, width: width, height: 1350)
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("statistics-\(name).png"))
        }
    }
}
