import SwiftUI

struct WidgetCard: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void
    var onOpenStatistics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.quotas) { q in
                ProviderSection(quota: q, settings: settings)
            }
            HStack(spacing: 6) {
                Text(store.lastUpdatedText)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(action: { store.refresh() }) {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        // 不设 maxHeight: .infinity —— 那会让 ideal 高度无定义，DesktopPanel.fitHeightToContent()
        // 量不出真实内容高度；窗口高度由 fit 跟随内容，卡片背景恰好铺满窗口。
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: settings.cornerRadius))
        .preferredColorScheme(settings.theme.colorScheme)
        .contextMenu {
            Button("刷新") { store.refresh() }
            Button("设置…") { onOpenSettings() }
            Button("统计…") { onOpenStatistics() }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
    }
}

struct ProviderSection: View {
    let quota: ProviderQuota
    @ObservedObject var settings: AppSettings

    var body: some View {
        let shown = quota.buckets.filter { settings.shouldShow($0.label) }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quota.displayName).font(.subheadline).fontWeight(.medium)
                Spacer()
                if quota.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            ForEach(shown) { b in QuotaRow(bucket: b) }
        }
    }
}
