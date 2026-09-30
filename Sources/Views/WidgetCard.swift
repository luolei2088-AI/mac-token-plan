import AppKit
import SwiftUI

struct WidgetCard: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var settings: AppSettings
    var onOpenSettings: () -> Void
    var onOpenStatistics: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("使用量").font(.headline)
                Spacer()
                Text("所有平台").font(.caption).foregroundStyle(.secondary)
                Button(action: { store.refresh() }) {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("刷新所有平台")
            }
            .padding(.bottom, 8)

            if store.quotas.isEmpty {
                Text(store.isRefreshing ? "正在获取用量…" : "暂无已配置的平台")
                    .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                ForEach(store.quotas) { quota in
                    if quota.id == "deepseek" {
                        DeepSeekProviderSection(quota: quota, settings: settings, store: store,
                                                onOpenStatistics: onOpenStatistics)
                            .id(quota.id)
                    } else {
                        ProviderSection(quota: quota, settings: settings, store: store,
                                        onOpenStatistics: onOpenStatistics)
                            .id(quota.id)
                    }
                    if let index = store.quotas.firstIndex(where: { $0.id == quota.id }),
                       index + 1 < store.quotas.count {
                        let nextID = store.quotas[index + 1].id
                        let isCodexDeepSeekPair = (quota.id == "codex" && nextID == "deepseek")
                            || (quota.id == "deepseek" && nextID == "codex")
                        if !isCodexDeepSeekPair {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
            }
            HStack {
                Text(store.lastUpdatedText).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("使用统计") { onOpenStatistics() }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                Button("设置") { onOpenSettings() }
                    .font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(12)
        .frame(minWidth: settings.quotaDisplayMode == .compact ? 224 : 336,
               idealWidth: settings.quotaDisplayMode == .compact ? 224 : 336,
               maxWidth: .infinity, alignment: .topLeading)
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

private struct ProviderSection: View {
    let quota: ProviderQuota
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: QuotaStore
    var onOpenStatistics: () -> Void
    @State private var showCodexDetail = false
    @State private var pointerInDetail = false
    @State private var hideTask: DispatchWorkItem?

    private var shown: [QuotaBucket] { quota.buckets.filter { settings.shouldShow($0.label) } }
    private var isCodex: Bool { quota.id == "codex" }
    @ViewBuilder var body: some View {
        if isCodex {
            providerRow.popover(isPresented: $showCodexDetail, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                CodexUsagePopover(store: store, onOpenStatistics: onOpenStatistics, onHover: updatePopoverHover)
                    .padding(12)
                    .background(.regularMaterial)
            }
        } else {
            providerRow
        }
    }

    private var providerRow: some View {
        Group {
            if settings.quotaDisplayMode == .compact { compactRow }
            else { detailedRows }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(showCodexDetail && isCodex ? Color.primary.opacity(0.055) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            guard isCodex else { return }
            if hovering {
                hideTask?.cancel()
                pointerInDetail = false
                showCodexDetail = true
                if store.codexAccount == nil { store.refreshCodexAccount() }
            } else {
                scheduleHide()
            }
        }
        .onTapGesture {
            if isCodex {
                if let url = URL(string: "https://chatgpt.com/") { NSWorkspace.shared.open(url) }
        } else if quota.id == "deepseek",
                  let url = URL(string: "https://platform.deepseek.com/usage") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var detailedRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            providerHeader
            if shown.isEmpty {
                Text(quota.error == nil ? "暂无可显示额度" : "获取失败")
                    .font(.caption2).foregroundStyle(quota.error == nil ? Color.secondary : Color.red)
            } else if isCodex {
                let accountBuckets = shown.filter { $0.source == "账户" }
                let modelBuckets = shown.filter { $0.source != "账户" }
                if !accountBuckets.isEmpty { quotaGrid(accountBuckets) }
                if !modelBuckets.isEmpty {
                    Divider().padding(.vertical, 3)
                    quotaGrid(modelBuckets)
                    Divider().padding(.vertical, 3)
                }
            } else {
                quotaGrid(shown)
            }
        }
        .padding(.horizontal, 6)
    }

    private func quotaGrid(_ buckets: [QuotaBucket]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(buckets) { bucket in MiniQuotaCell(bucket: bucket) }
        }
    }

    private var compactRow: some View {
        HStack(spacing: 7) {
            providerIcon
            Text(quota.displayName).font(.subheadline).fontWeight(.medium).lineLimit(1)
            Spacer(minLength: 5)
            if let balance = shown.first(where: { $0.balanceAmount != nil }),
               balance.balanceAmount != nil {
                Text(balance.compactSummary)
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            } else if let bucket = shown.max(by: { $0.percent < $1.percent }) {
                Text(bucket.compactSummary)
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            } else if quota.error != nil {
                Text("获取失败").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 24)
    }

    private var providerHeader: some View {
        HStack(spacing: 7) {
            providerIcon
            Text(quota.displayName).font(.subheadline).fontWeight(.medium).lineLimit(1)
            if isCodex, let plan = store.codexAccount?.planType {
                Text(planTitle(plan)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 3)
            if quota.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            } else if let reset = earliestReset {
                Text("重置 \(shortCountdown(reset))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var providerIcon: some View {
        Group {
            if isCodex {
                CodexBrandIcon(size: 16)
            } else if quota.id == "deepseek" {
                DeepSeekBrandIcon(size: 16)
            } else {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
            .frame(width: 18, height: 18)
    }

    private var earliestReset: Date? { shown.compactMap(\.resetTime).min() }

    private func scheduleHide() {
        hideTask?.cancel()
        let task = DispatchWorkItem {
            if !pointerInDetail {
                showCodexDetail = false
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    private func updatePopoverHover(_ inside: Bool) {
        pointerInDetail = inside
        if inside { hideTask?.cancel() } else { scheduleHide() }
    }

    private func shortCountdown(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 { return "\(days)天\(hours)小时" }
        return "\(max(1, seconds / 60))分钟"
    }

    private func planTitle(_ plan: String) -> String {
        let titles: [String: String] = [
            "prolite": "Pro Lite", "promax": "Pro Max", "plus": "Plus",
            "pro": "Pro", "free": "Free", "team": "Team",
        ]
        return titles[plan.lowercased()] ?? plan.capitalized
    }
}

/// DeepSeek 使用独立 AppKit NSPopover，不参与 Codex 的 SwiftUI popover 呈现状态。
private struct DeepSeekProviderSection: View {
    let quota: ProviderQuota
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: QuotaStore
    var onOpenStatistics: () -> Void
    var body: some View {
        ProviderSection(quota: quota, settings: settings, store: store,
                        onOpenStatistics: onOpenStatistics)
            .overlay {
                DeepSeekPopoverAnchor(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
    }
}

private struct DeepSeekPopoverAnchor: NSViewRepresentable {
    let store: QuotaStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        context.coordinator.attach(view)
        view.onHover = { [weak coordinator = context.coordinator] inside in
            coordinator?.anchorHover(inside)
        }
        return view
    }

    func updateNSView(_ view: HoverTrackingNSView, context: Context) {
        context.coordinator.store = store
        context.coordinator.attach(view)
        view.onHover = { [weak coordinator = context.coordinator] inside in
            coordinator?.anchorHover(inside)
        }
    }

    static func dismantleNSView(_ view: HoverTrackingNSView, coordinator: Coordinator) {
        view.onHover = nil
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var store: QuotaStore
        private weak var anchorView: HoverTrackingNSView?
        private var popover: NSPopover?
        private var closeTask: DispatchWorkItem?
        private var pointerInAnchor = false
        private var pointerInPopover = false

        init(store: QuotaStore) { self.store = store }

        func attach(_ view: HoverTrackingNSView) { anchorView = view }

        func anchorHover(_ inside: Bool) {
            pointerInAnchor = inside
            if inside {
                closeTask?.cancel()
                pointerInPopover = false
                if store.deepSeekAccount == nil && !store.isLoadingDeepSeekAccount {
                    store.refreshDeepSeekAccount()
                }
                show()
            } else {
                scheduleClose()
            }
        }

        private func show() {
            guard let anchorView, anchorView.window != nil else {
                return
            }
            if let popover, popover.isShown { return }

            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = NSHostingController(
                rootView: DeepSeekUsagePopover(store: store, onHover: { [weak self] inside in
                    self?.popoverHover(inside)
                })
                .padding(12)
                .background(.regularMaterial)
            )
            self.popover = popover
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
        }

        private func scheduleClose() {
            closeTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if !self.pointerInAnchor && !self.pointerInPopover {
                    self.popover?.performClose(nil)
                }
            }
            closeTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
        }

        private func popoverHover(_ inside: Bool) {
            pointerInPopover = inside
            if inside { closeTask?.cancel() } else { scheduleClose() }
        }

        func close() {
            closeTask?.cancel()
            popover?.performClose(nil)
        }

        func popoverDidClose(_ notification: Notification) {
            closeTask?.cancel()
            pointerInAnchor = false
            pointerInPopover = false
            popover = nil
        }
    }
}

private struct HoverTrackingView: NSViewRepresentable {
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: HoverTrackingNSView, context: Context) {
        view.onHover = onHover
    }
}

private final class HoverTrackingNSView: NSView {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let newArea = NSTrackingArea(rect: bounds,
                                     options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                     owner: self,
                                     userInfo: nil)
        addTrackingArea(newArea)
        area = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        let frontmostWindow = NSWindow.windowNumber(at: mouseLocation, belowWindowWithWindowNumber: 0)
        let anchorWindow = window?.windowNumber ?? 0
        guard frontmostWindow == anchorWindow else {
            return
        }
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

private struct MiniQuotaCell: View {
    let bucket: QuotaBucket

    var body: some View {
        Group {
            if let amount = bucket.balanceAmount {
                HStack(spacing: 4) {
                    Text(bucket.displayLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(bucket.currencySymbol)\(String(format: "%.2f", amount))")
                        .font(.caption2).monospacedDigit().lineLimit(1)
                }
            } else {
                HStack(spacing: 4) {
                    Text(bucket.displayLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.14))
                            Capsule().fill(color).frame(width: max(2, geometry.size.width * bucket.percent))
                        }
                    }
                    .frame(height: 5)
                    Text("\(Int(bucket.percent * 100))%")
                        .font(.caption2).monospacedDigit().frame(minWidth: 27, alignment: .trailing)
                }
            }
        }
        .frame(minHeight: 12)
        .help(bucket.resetTime.map { "\(bucket.displayLabel) · \(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short)) 重置" } ?? bucket.displayLabel)
    }

    private var color: Color {
        if bucket.percent >= 0.95 { return .red }
        if bucket.percent >= 0.70 { return .orange }
        return .green
    }
}

private struct CodexUsagePopover: View {
    @ObservedObject var store: QuotaStore
    var onOpenStatistics: () -> Void
    var onHover: (Bool) -> Void
    @State private var confirmReset = false
    @State private var selectedResetCard: CodexResetCredit?
    @State private var copiedModelID: String?

    private var snapshot: CodexAccountSnapshot? { store.codexAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
                header
                Divider()
                if let snapshot {
                if let error = store.codexAccountError {
                    Label("刷新失败：\(error)", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                accountLine(snapshot)
                if let allowed = snapshot.ordinaryUsageAllowed {
                    Label(allowed ? "当前可正常使用" : "当前用量受到限制",
                          systemImage: allowed ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(allowed ? Color.secondary : Color.orange)
                }
                rateLimits(snapshot)
                availableModels(snapshot)
                resetCards(snapshot)
                tokenSummary(snapshot)
                } else if let error = store.codexAccountError {
                    Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在读取 Codex 账户信息…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let result = store.codexResetResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Button("使用统计", action: onOpenStatistics)
                    Spacer()
                    Button { store.refreshCodexAccount() } label: { Image(systemName: "arrow.clockwise") }
                        .help("刷新 Codex 信息")
                }
                .font(.caption)
                .buttonStyle(.plain)
        }
        .frame(width: 366, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            HoverTrackingView(onHover: onHover)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .confirmationDialog("确认使用此重置卡？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("立即重置", role: .destructive) {
                guard let credit = selectedResetCard else { return }
                Task { await store.consumeCodexReset(creditID: credit.id) }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("将使用「\(selectedResetCard?.title ?? "Codex 用量重置")」，消耗这张卡并重置当前符合条件的额度窗口。")
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            CodexBrandIcon(size: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex").font(.subheadline).fontWeight(.semibold)
                Text(snapshot.map { "更新于 \(DateFormatter.localizedString(from: $0.fetchedAt, dateStyle: .none, timeStyle: .short))" } ?? "账户用量")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private func accountLine(_ snapshot: CodexAccountSnapshot) -> some View {
        HStack(spacing: 4) {
            Text(planTitle(snapshot.planType)).font(.caption).fontWeight(.medium)
            if let email = snapshot.email, !email.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private func rateLimits(_ snapshot: CodexAccountSnapshot) -> some View {
        let limits = snapshot.allRateLimits
        if !limits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(limits) { limit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(limit.limitName ?? sourceTitle(limit.limitId))
                            .font(.caption).fontWeight(.medium).lineLimit(1)
                        if let primary = limit.primary { rateWindow(primary) }
                        if let secondary = limit.secondary { rateWindow(secondary) }
                        if let spend = limit.individualLimit {
                            HStack {
                                Text("额外用量")
                                Spacer()
                                Text("\(spend.used) / \(spend.limit)")
                            }.font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func rateWindow(_ window: CodexRateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                Spacer()
                Text("\(window.usedPercent)%")
                if let date = window.resetDate {
                    Text("重置 \(shortCountdown(date))").foregroundStyle(.secondary)
                }
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule().fill(window.usedPercent >= 95 ? Color.red : (window.usedPercent >= 70 ? .orange : .green))
                        .frame(width: max(2, geometry.size.width * min(1, max(0, Double(window.usedPercent) / 100))))
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder private func resetCards(_ snapshot: CodexAccountSnapshot) -> some View {
        let resetCards = snapshot.rateLimitResetCredits?.credits?.filter { $0.status == "available" } ?? []
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("用量重置卡").font(.caption).fontWeight(.medium)
                Spacer()
                Text("可用 \(snapshot.resetCreditCount) 张").font(.caption).foregroundStyle(.secondary)
            }
            if resetCards.isEmpty && snapshot.resetCreditCount == 0 {
                Text("暂无可用重置卡").font(.caption2).foregroundStyle(.secondary)
            } else if !resetCards.isEmpty {
                ForEach(resetCards) { credit in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit.title ?? "Codex 用量重置")
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(credit.expiryDate.map { "有效至 \(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none))" } ?? "无到期时间")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(store.isConsumingCodexReset ? "重置中…" : "使用") {
                            selectedResetCard = credit
                            confirmReset = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.isConsumingCodexReset)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("重置卡详情暂不可用").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func tokenSummary(_ snapshot: CodexAccountSnapshot) -> some View {
        if let summary = snapshot.usage?.summary {
            VStack(alignment: .leading, spacing: 3) {
                if let lifetime = summary.lifetimeTokens {
                    Text("累计 \(lifetime.formatted()) tokens").font(.caption2).foregroundStyle(.secondary)
                }
                if let peak = summary.peakDailyTokens {
                    Text("单日峰值 \(peak.formatted()) tokens").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func availableModels(_ snapshot: CodexAccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("当前可用模型").font(.caption).fontWeight(.medium)
                Spacer()
                Text("\(snapshot.models.count) 个").font(.caption2).foregroundStyle(.secondary)
            }
            if snapshot.models.isEmpty {
                Text(snapshot.modelsError.map { "暂时无法读取：\($0)" } ?? "当前没有可显示的模型")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(snapshot.models) { model in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Button { copyModelName(model.model) } label: {
                                HStack(spacing: 4) {
                                    Text(model.displayName).font(.caption2).fontWeight(.medium).lineLimit(1)
                                    if copiedModelID == model.model {
                                        Text("已复制").font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("点击复制模型名称")
                            if model.isDefault {
                                Text("默认").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        Text(model.model).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        if !model.supportedReasoningEfforts.isEmpty {
                            Text("推理：\(model.supportedReasoningEfforts.map(\.reasoningEffort).joined(separator: "、"))")
                                .font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func copyModelName(_ name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        copiedModelID = name
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedModelID == name { copiedModelID = nil }
        }
    }

    private func sourceTitle(_ source: String?) -> String {
        if source == "codex" { return "账户额度" }
        return source ?? "Codex 额度"
    }

    private func planTitle(_ plan: String?) -> String {
        guard let plan else { return "Codex 订阅" }
        let titles: [String: String] = [
            "prolite": "Pro Lite", "promax": "Pro Max", "plus": "Plus",
            "pro": "Pro", "free": "Free", "team": "Team",
        ]
        return titles[plan.lowercased()] ?? plan.capitalized
    }

    private func shortCountdown(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 { return "\(days)天\(hours)小时" }
        return "\(max(1, seconds / 60))分钟"
    }
}

private struct DeepSeekUsagePopover: View {
    @ObservedObject var store: QuotaStore
    var onHover: (Bool) -> Void
    @State private var copiedModelID: String?

    private var snapshot: DeepSeekAccountSnapshot? { store.deepSeekAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                DeepSeekBrandIcon(size: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DeepSeek").font(.subheadline).fontWeight(.semibold)
                    Text(snapshot.map { "更新于 \(DateFormatter.localizedString(from: $0.fetchedAt, dateStyle: .none, timeStyle: .short))" } ?? "账户与模型")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            if let snapshot {
                if let error = store.deepSeekAccountError {
                    Label("刷新失败：\(error)", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let available = snapshot.isAvailable {
                    Label(available ? "账户可正常调用" : "账户余额不足，暂不可调用",
                          systemImage: available ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(available ? Color.secondary : Color.orange)
                }
                balanceDetails(snapshot)
                modelDetails(snapshot)
            } else if let error = store.deepSeekAccountError {
                Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取账户与模型信息…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button("打开用量页面") {
                    if let url = URL(string: "https://platform.deepseek.com/usage") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                Spacer()
                Button { store.refreshDeepSeekAccount() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新 DeepSeek 账户与模型")
            }
        }
        .frame(width: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            HoverTrackingView(onHover: onHover)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func balanceDetails(_ snapshot: DeepSeekAccountSnapshot) -> some View {
        if snapshot.balanceInfos.isEmpty {
            Text("暂无余额数据").font(.caption2).foregroundStyle(.secondary)
        } else {
            ForEach(snapshot.balanceInfos) { balance in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(balance.currency.map { "\($0) 余额" } ?? "余额")
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                        Text(money(balance.totalBalance, currency: balance.currency))
                            .font(.caption).monospacedDigit()
                    }
                    HStack {
                        Text("充值 \(money(balance.toppedUpBalance, currency: balance.currency))")
                        Spacer()
                        Text("赠金 \(money(balance.grantedBalance, currency: balance.currency))")
                    }
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder private func modelDetails(_ snapshot: DeepSeekAccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("当前可用模型").font(.caption).fontWeight(.medium)
                Spacer()
                Text("\(snapshot.models.count) 个").font(.caption2).foregroundStyle(.secondary)
            }
            if snapshot.models.isEmpty {
                Text(snapshot.modelsError ?? "暂无可用模型")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(snapshot.models) { model in
                    VStack(alignment: .leading, spacing: 2) {
                        Button { copyModelName(model.modelID) } label: {
                            HStack(spacing: 4) {
                                Text(model.name ?? model.modelID).font(.caption2).fontWeight(.medium)
                                if copiedModelID == model.modelID {
                                    Text("已复制").font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("点击复制模型名称")
                        Text(model.modelID).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 8) {
                            if let context = model.contextWindow { Text("上下文 \(context.formatted())") }
                            if let output = model.maxOutputTokens { Text("最大输出 \(output.formatted())") }
                        }
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func copyModelName(_ name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        copiedModelID = name
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedModelID == name { copiedModelID = nil }
        }
    }

    private func money(_ value: String?, currency: String?) -> String {
        let symbol = currency == "USD" ? "$" : (currency == "CNY" ? "¥" : "")
        guard let value else { return "—" }
        return "\(symbol)\(value)"
    }
}
