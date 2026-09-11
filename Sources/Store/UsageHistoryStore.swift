import Foundation

struct UsageSample: Codable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(providerID)-\(source ?? "")-\(label)" }
    let providerID: String
    let source: String?
    let label: String
    let timestamp: Date
    let percent: Double
}

struct UsagePoint: Identifiable {
    let id: Date
    let date: Date
    let providerID: String
    let source: String?
    let label: String
    let percent: Double
}

@MainActor
final class UsageHistoryStore: ObservableObject {
    @Published private(set) var samples: [UsageSample] = []
    private var previous: [String: UsageSample] = [:]
    private let calendar: Calendar
    private let fileURL: URL
    private let retention: TimeInterval = 90 * 86400

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        calendar = cal
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mac-token-plan", isDirectory: true)
        fileURL = dir.appendingPathComponent("usage-history.json")
        load()
    }

    func record(_ quotas: [ProviderQuota], at date: Date = Date()) {
        for quota in quotas where quota.error == nil {
            for bucket in quota.buckets {
                let key = Self.key(quota.id, bucket.source, bucket.label)
                let current = UsageSample(providerID: quota.id, source: bucket.source,
                                          label: bucket.label, timestamp: date,
                                          percent: bucket.percent * 100)
                if let old = previous[key] {
                    let reset = bucket.resetTime != nil && old.timestamp < date &&
                        (bucket.resetTime! <= date || current.percent < old.percent)
                    let delta = reset ? current.percent : max(0, current.percent - old.percent)
                    if delta <= 100 {
                        samples.append(UsageSample(providerID: quota.id, source: bucket.source,
                                                   label: bucket.label, timestamp: date, percent: delta))
                    }
                } else {
                    // 首次成功采样没有可比较的前值，但仍记录当前观测值，
                    // 否则新安装/重启后统计页会长期显示“暂无数据”。
                    samples.append(UsageSample(providerID: quota.id, source: bucket.source,
                                               label: bucket.label, timestamp: date,
                                               percent: current.percent))
                }
                previous[key] = current
            }
        }
        pruneAndSave(now: date)
    }

    func points(period: UsagePeriod, providerID: String? = nil, label: String? = nil) -> [UsagePoint] {
        let now = Date()
        let start = calendar.date(byAdding: period.calendarComponent, value: -period.amount, to: now) ?? now
        let filtered = samples.filter { $0.timestamp >= start &&
            (providerID == nil || $0.providerID == providerID) &&
            (label == nil || $0.label == label) }
        let grouped = Dictionary(grouping: filtered) { sample in
            let date = period == .oneDay ? calendar.dateInterval(of: .hour, for: sample.timestamp)!.start :
                calendar.startOfDay(for: sample.timestamp)
            return "\(date.timeIntervalSince1970)|\(sample.providerID)|\(sample.source ?? "")|\(sample.label)"
        }
        return grouped.compactMap { _, values in
            guard let first = values.first else { return nil }
            let date = period == .oneDay ? calendar.dateInterval(of: .hour, for: first.timestamp)!.start : calendar.startOfDay(for: first.timestamp)
            return UsagePoint(id: date, date: date, providerID: first.providerID, source: first.source,
                              label: first.label, percent: values.reduce(0) { $0 + $1.percent })
        }.sorted { $0.date < $1.date }
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
}
