import SwiftUI
import Charts

struct UsageStatisticsView: View {
    @ObservedObject var history: UsageHistoryStore
    let settings: AppSettings
    @State private var period: UsagePeriod = .sevenDays
    @State private var providerID: String?
    @State private var label: String?

    private var providerNames: [(String, String)] {
        AppSettings.allPlatforms.map { ($0.id, $0.name) }
    }
    private var points: [UsagePoint] { history.points(period: period, providerID: providerID, label: label) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("范围", selection: $period) { ForEach(UsagePeriod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                Picker("渠道", selection: $providerID) {
                    Text("全部渠道").tag(String?.none)
                    ForEach(providerNames, id: \.0) { Text($0.1).tag(Optional($0.0)) }
                }
                Picker("窗口", selection: $label) {
                    Text("全部窗口").tag(String?.none)
                    Text("5小时").tag(Optional("5小时")); Text("7天").tag(Optional("7天")); Text("总额度").tag(Optional("总额度"))
                }
            }
            if points.isEmpty {
                ContentUnavailableView("暂无统计数据", systemImage: "chart.bar.xaxis", description: Text("应用运行并完成至少两次刷新后开始记录。"))
            } else {
                Chart(points) { point in
                    BarMark(x: .value("时间", point.date), y: .value("使用量", point.percent))
                        .foregroundStyle(by: .value("渠道", title(for: point.providerID)))
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("已用百分比")
                .frame(minHeight: 260)
                Text("图表显示采样期间的使用增量；未采样或刷新失败时保留空档。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .preferredColorScheme(settings.theme.colorScheme)
        .frame(minWidth: 760, minHeight: 380)
    }

    private func title(for id: String) -> String { providerNames.first { $0.0 == id }?.1 ?? id }
}
