import SwiftUI
import Charts

struct UsageStatisticsView: View {
    @ObservedObject var history: UsageHistoryStore
    @ObservedObject var settings: AppSettings
    @State private var period: UsagePeriod = .sevenDays
    @State private var providerID: String?
    @State private var window: String?
    @State private var hoveredDate: Date?
    @State private var now = Date()
    @State private var allPoints: [UsagePoint]

    init(history: UsageHistoryStore, settings: AppSettings, period: UsagePeriod = .sevenDays,
         hoveredDate: Date? = nil) {
        self.history = history
        self.settings = settings
        _period = State(initialValue: period)
        _hoveredDate = State(initialValue: hoveredDate)
        let snapshotDate = Date()
        _now = State(initialValue: snapshotDate)
        _allPoints = State(initialValue: history.points(period: period, now: snapshotDate))
    }

    private let colors: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo]
    private var enabledPoints: [UsagePoint] {
        let enabled = Set(providers)
        return allPoints.filter { enabled.contains($0.providerID) }
    }
    private var windows: [String] {
        Set(enabledPoints.filter { providerID == nil || $0.providerID == providerID }
            .map { $0.series.windowTitle }).sorted()
    }
    private var windowPoints: [UsagePoint] {
        enabledPoints.filter { window == nil || $0.series.windowTitle == window }
    }
    private var points: [UsagePoint] {
        windowPoints.filter { providerID == nil || $0.providerID == providerID }
    }
    private var providers: [String] { settings.enabledProviderIDs }
    private func orderedSeries(_ points: [UsagePoint]) -> [UsageSeries] {
        let order = providers
        return Array(Set(points.map(\.series))).sorted {
            let a = order.firstIndex(of: $0.providerID) ?? Int.max
            let b = order.firstIndex(of: $1.providerID) ?? Int.max
            return a == b ? $0.id < $1.id : a < b
        }
    }
    private var metrics: [UsageMetric] {
        Set(points.map { $0.series.metric }).sorted { $0 != $1 && ($0 == .quota || ($1 != .quota && $0.id < $1.id)) }
    }
    private var range: ClosedRange<Date> { period.range(endingAt: now) }
    private var chartRange: ClosedRange<Date> { period.bucketStart(range.lowerBound)...period.bucketEnd(period.bucketStart(now)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                controls
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(providers, id: \.self) { id in providerCard(id) }
                }
                if points.isEmpty {
                    ContentUnavailableView(providers.isEmpty ? "尚未开启渠道" : "暂无统计数据", systemImage: "chart.bar.xaxis",
                        description: Text(providers.isEmpty ? "请在设置中开启需要统计的渠道。" : "需要至少两次成功刷新才能计算消耗；也可调整筛选范围。"))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(metric.title).font(.headline)
                                Spacer()
                                Text("\(period == .oneDay ? "按小时汇总" : "按日汇总") · 单位：\(metric.unit)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            usageChart(metric)
                            legend(metric)
                        }
                        .padding(20)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Label("统计为采样期间记录到的额度消耗增量，不同额度窗口独立计算。", systemImage: "info.circle")
                    Text("空档表示无采样数据；离线期间的完整消耗无法还原。旧版本历史记录可能包含启动时的已用额度。")
                    if providers.contains("deepseek") || metrics.contains(where: { $0 != .quota }) {
                        Text("金额花销按余额减少额估算，从新版成功采样后开始记录；余额增加不计花销，充值、赠金变化可能影响估算，实际费用以平台账单为准。")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(settings.theme.colorScheme)
        .frame(minWidth: 820, minHeight: 560)
        .onReceive(history.$samples.dropFirst().debounce(for: .milliseconds(50), scheduler: RunLoop.main)) { _ in refreshPoints() }
        .onChange(of: period) { _, _ in refreshPoints() }
        .onChange(of: providers) { _, enabled in
            if let providerID, !enabled.contains(providerID) { self.providerID = nil }
            resetSelection()
        }
        .onChange(of: providerID) { _, _ in resetSelection() }
        .onChange(of: window) { _, _ in hoveredDate = nil }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("使用量统计").font(.system(size: 25, weight: .bold))
                Text("了解各渠道的额度消耗与使用节奏").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(formatDate(range.lowerBound)) — \(formatDate(now))")
                Text("本地时间 · \(TimeZone.current.identifier)")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Picker("范围", selection: $period) {
                ForEach(UsagePeriod.allCases) { Text("近\($0.rawValue)").tag($0) }
            }.pickerStyle(.segmented).frame(width: 225)
            Picker("渠道", selection: $providerID) {
                Text("已开启渠道").tag(String?.none)
                ForEach(providers, id: \.self) { Text(title(for: $0)).tag(Optional($0)) }
            }
            Picker("统计维度", selection: $window) {
                Text("全部维度").tag(String?.none)
                ForEach(windows, id: \.self) { Text($0).tag(Optional($0)) }
            }
        }
    }

    private func providerCard(_ id: String) -> some View {
        let totals = Dictionary(grouping: windowPoints.filter { $0.providerID == id }, by: \.series)
        let entries = totals.keys.sorted { $0.id < $1.id }
        return Button {
            providerID = providerID == id ? nil : id
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RoundedRectangle(cornerRadius: 3).fill(color(for: id)).frame(width: 6, height: 20)
                    Text(title(for: id)).font(.headline)
                    Spacer(minLength: 0)
                    if providerID == id { Image(systemName: "checkmark.circle.fill").foregroundStyle(color(for: id)) }
                }
                if entries.isEmpty {
                    Text(id == "deepseek" ? "暂无花销数据，等待余额采样" : "所选范围无采样数据")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.currency == nil ? entry.windowTitle : "近\(period.rawValue)花销").font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(valueText(totals[entry, default: []].reduce(0) { $0 + $1.value }, metric: entry.metric))
                                .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                            Text(entry.metric.unit).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(color(for: id).opacity(providerID == id ? 0.10 : 0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color(for: id).opacity(providerID == id ? 0.65 : 0.18)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(for: id))，点击\(providerID == id ? "取消" : "按渠道")筛选")
    }

    private func usageChart(_ metric: UsageMetric) -> some View {
        let points = points.filter { $0.series.metric == metric }
        let series = orderedSeries(points)
        let chartPoints = series.flatMap { item in points.filter { $0.series == item } }
        let maximum = points.map(\.value).max() ?? 0
        let yMaximum = maximum == 0 ? (metric == .quota ? 10 : 1) : maximum * 1.15
        return Chart {
            ForEach(chartPoints) { point in
                BarMark(x: .value("时间", point.date, unit: period.bucketComponent),
                        y: .value("消耗", point.value), stacking: .unstacked)
                    .position(by: .value("系列", point.series.id))
                    .foregroundStyle(by: .value("系列", point.series.id))
                    .cornerRadius(3)
                    .accessibilityLabel("\(seriesTitle(point.series))，\(formatDate(point.date))")
                    .accessibilityValue("\(valueText(point.value, metric: metric)) \(metric.unit)")
            }
            if let hoveredDate {
                RuleMark(x: .value("选中时间", hoveredDate, unit: period.bucketComponent))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: chartRange)
        .chartXScale(range: .plotDimension(startPadding: 18, endPadding: 24))
        .chartYScale(domain: 0...yMaximum)
        .chartForegroundStyleScale(domain: series.map(\.id), range: series.map { seriesColor($0, series: series) })
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: period.bucketComponent, count: period == .oneDay ? 4 : (period == .sevenDays ? 1 : 5))) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisDate(date)).font(.caption2).fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let anchor = proxy.plotFrame else { return }
                            let frame = geometry[anchor]
                            guard frame.contains(location),
                                  let date: Date = proxy.value(atX: location.x - frame.minX) else {
                                hoveredDate = nil
                                return
                            }
                            hoveredDate = period.bucketStart(date)
                        case .ended: hoveredDate = nil
                        }
                    }
                if let date = hoveredDate, let anchor = proxy.plotFrame {
                    let frame = geometry[anchor]
                    let x = (proxy.position(forX: date) ?? 0) + frame.minX
                    hoverDetails(date, metric: metric)
                        .frame(width: 300)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .offset(x: max(0, min(x > frame.midX ? x - 338 : x + 14, geometry.size.width - 324)), y: 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: max(300, CGFloat(series.count) * 23 + 60))
    }

    private func hoverDetails(_ date: Date, metric: UsageMetric) -> some View {
        let points = points.filter { $0.series.metric == metric }
        let series = orderedSeries(points)
        let start = max(date, range.lowerBound)
        let end = min(period.bucketEnd(date), now)
        let values = points.filter { $0.date == date }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(formatDate(start)) — \(formatDate(end))").font(.caption).bold()
            Divider()
            ForEach(series) { item in
                HStack(alignment: .firstTextBaseline) {
                    Circle().fill(seriesColor(item, series: series)).frame(width: 6, height: 6)
                    Text(seriesTitle(item)).lineLimit(2)
                    Spacer(minLength: 4)
                    if let point = values.first(where: { $0.series == item }) {
                        Text("\(valueText(point.value, metric: metric))\(metric == .quota ? "" : " ")\(metric.unit)").monospacedDigit().bold()
                    } else {
                        Text("无采样数据").foregroundStyle(.secondary)
                    }
                }.font(.caption)
            }
            Text(metric == .quota ? "所选时段额度消耗增量" : "按余额减少额估算").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func legend(_ metric: UsageMetric) -> some View {
        let series = orderedSeries(points.filter { $0.series.metric == metric })
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(series) { item in
                HStack(spacing: 6) {
                    Circle().fill(seriesColor(item, series: series)).frame(width: 7, height: 7)
                    Text(seriesTitle(item)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refreshPoints() {
        now = Date()
        allPoints = history.points(period: period, now: now)
        resetSelection()
    }
    private func resetSelection() {
        hoveredDate = nil
        if let window, !windows.contains(window) { self.window = nil }
    }
    private func title(for id: String) -> String { AppSettings.allPlatforms.first { $0.id == id }?.name ?? id }
    private func seriesTitle(_ series: UsageSeries) -> String { "\(title(for: series.providerID)) · \(series.windowTitle)" }
    private func color(for id: String) -> Color {
        colors[(AppSettings.defaultProviderOrder.firstIndex(of: id) ?? 0) % colors.count]
    }
    private func seriesColor(_ item: UsageSeries, series: [UsageSeries]) -> Color {
        let siblings = series.filter { $0.providerID == item.providerID }
        let index = siblings.firstIndex(of: item) ?? 0
        return color(for: item.providerID).opacity(max(0.4, 1 - Double(index) * 0.18))
    }
    private func valueText(_ value: Double, metric: UsageMetric) -> String {
        if metric == .quota { return value.formatted(.number.precision(.fractionLength(0...2))) }
        if value > 0 && value < 0.000001 { return "<0.000001" }
        return value.formatted(.number.precision(.fractionLength(2...6)))
    }
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
    private func axisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = period == .oneDay ? "M/d\nHH:mm" : "M/d"
        return formatter.string(from: date)
    }
}
