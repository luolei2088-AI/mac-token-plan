import Foundation

struct UsageSample: Codable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(providerID)-\(source ?? "")-\(label)-\(currency ?? "quota")" }
    let providerID: String
    let source: String?
    let label: String
    let timestamp: Date
    let percent: Double
    var amount: Double? = nil
    var currency: String? = nil
}

struct UsagePoint: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)|\(series.id)" }
    var series: UsageSeries { UsageSeries(providerID: providerID, source: source, label: label, currency: currency) }
    let date: Date
    let providerID: String
    let source: String?
    let label: String
    let percent: Double
    var amount: Double? = nil
    var currency: String? = nil
    var value: Double { amount ?? percent }
}

struct UsageSeries: Hashable, Identifiable {
    let providerID: String
    let source: String?
    let label: String
    var currency: String? = nil
    var metric: UsageMetric { currency.map { .money($0) } ?? .quota }
    var id: String { "\(providerID)|\(source ?? "")|\(label)|\(metric.id)" }
    var windowTitle: String { currency.map { "花销（\($0)）" } ?? (source.map { "\($0)·\(label)" } ?? label) }
}

enum UsageMetric: Hashable, Identifiable {
    case quota
    case money(String)
    var id: String { switch self { case .quota: return "quota"; case .money(let currency): return "money:\(currency)" } }
    var unit: String { switch self { case .quota: return "%"; case .money(let currency): return currency } }
    var title: String { self == .quota ? "额度消耗趋势" : "金额花销趋势（\(unit)）" }
}

@MainActor
final class UsageHistoryStore: ObservableObject {
    @Published private(set) var samples: [UsageSample] = []
    private var previous: [String: UsageSample] = [:]
    private var previousBalances: [String: (date: Date, amount: Decimal)] = [:]
    private var previousResetTimes: [String: Date] = [:]
    private let calendar: Calendar
    private let fileURL: URL
    private let retention: TimeInterval = 90 * 86400

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mac-token-plan", isDirectory: true)
        self.fileURL = fileURL ?? dir.appendingPathComponent("usage-history.json")
        load()
    }

    func record(_ quotas: [ProviderQuota], at date: Date = Date()) {
        for quota in quotas where quota.error == nil {
            for bucket in quota.buckets {
                if let balance = bucket.balanceAmount {
                    recordBalance(balance, bucket: bucket, providerID: quota.id, at: date)
                    continue
                }
                let key = Self.key(quota.id, bucket.source, bucket.label)
                let current = UsageSample(providerID: quota.id, source: bucket.source,
                                          label: bucket.label, timestamp: date,
                                          percent: bucket.percent * 100)
                if let old = previous[key] {
                    guard date > old.timestamp else { continue }
                    let crossedReset = previousResetTimes[key].map { old.timestamp < $0 && $0 <= date } ?? false
                    let reset = crossedReset || current.percent < old.percent
                    let delta = reset ? current.percent : max(0, current.percent - old.percent)
                    if delta <= 100 {
                        samples.append(UsageSample(providerID: quota.id, source: bucket.source,
                                                   label: bucket.label, timestamp: date, percent: delta))
                    }
                }
                previous[key] = current
                previousResetTimes[key] = bucket.resetTime
            }
        }
        pruneAndSave(now: date)
    }

    func points(period: UsagePeriod, providerID: String? = nil, label: String? = nil,
                now: Date = Date()) -> [UsagePoint] {
        let range = period.range(endingAt: now, calendar: calendar)
        let filtered = samples.filter { range.contains($0.timestamp) &&
            ($0.amount != nil || !$0.label.hasPrefix("余额")) &&
            (providerID == nil || $0.providerID == providerID) &&
            (label == nil || $0.label == label) }
        struct Key: Hashable {
            let date: Date
            let series: UsageSeries
        }
        let grouped = Dictionary(grouping: filtered) { sample in
            Key(date: period.bucketStart(sample.timestamp, calendar: calendar),
                series: UsageSeries(providerID: sample.providerID, source: sample.source, label: sample.label,
                                    currency: sample.amount == nil ? nil : (sample.currency ?? "未知币种")))
        }
        return grouped.map { key, values in
            UsagePoint(date: key.date, providerID: key.series.providerID, source: key.series.source,
                       label: key.series.label, percent: values.reduce(0) { $0 + $1.percent },
                       amount: key.series.currency == nil ? nil : values.reduce(0) { $0 + ($1.amount ?? 0) },
                       currency: key.series.currency)
        }.sorted { $0.date == $1.date ? $0.series.id < $1.series.id : $0.date < $1.date }
    }

    private func recordBalance(_ balance: Double, bucket: QuotaBucket, providerID: String, at date: Date) {
        guard balance.isFinite, let amount = Decimal(string: String(balance), locale: Locale(identifier: "en_US_POSIX")) else { return }
        let currency = bucket.currency ?? "未知币种"
        let key = "\(Self.key(providerID, bucket.source, bucket.label))|\(currency)"
        if let old = previousBalances[key] {
            guard date > old.date else { return }
            // Balance increases establish a new baseline, never a negative expense.
            let delta = max(Decimal.zero, old.amount - amount)
            samples.append(UsageSample(providerID: providerID, source: bucket.source, label: bucket.label,
                timestamp: date, percent: 0, amount: NSDecimalNumber(decimal: delta).doubleValue, currency: currency))
        }
        previousBalances[key] = (date, amount)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([UsageSample].self, from: data) else { return }
        samples = decoded
    }

    private func pruneAndSave(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.timestamp) > retention }
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func key(_ provider: String, _ source: String?, _ label: String) -> String { "\(provider)|\(source ?? "")|\(label)" }
}

enum UsagePeriod: String, CaseIterable, Identifiable {
    case oneDay = "1天", sevenDays = "7天", thirtyDays = "30天"
    var id: String { rawValue }
    var amount: Int { self == .oneDay ? 1 : (self == .sevenDays ? 7 : 30) }
    var calendarComponent: Calendar.Component { .day }
    var bucketComponent: Calendar.Component { self == .oneDay ? .hour : .day }
    func range(endingAt now: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        (calendar.date(byAdding: .day, value: -amount, to: now) ?? now)...now
    }
    func bucketStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: bucketComponent, for: date)!.start
    }
    func bucketEnd(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: bucketComponent, value: 1, to: date)!
    }
}
