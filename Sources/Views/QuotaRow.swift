import SwiftUI

struct QuotaRow: View {
    let bucket: QuotaBucket
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(bucket.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reset = bucket.resetTime {
                    Text(countdownText(reset, now: now, label: bucket.label))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
                }
                Spacer()
                Text("已使用 \(Int(bucket.percent * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color)
                        .frame(width: max(2, geo.size.width * bucket.percent))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
        }
    }

    /// 按已用占比渐变：<70% 绿，70-90% 绿渐变到橙，90-100% 橙渐变到红
    private var color: Color {
        let p = bucket.percent
        let (gh, gs, gb) = (0.35, 0.4, 0.65)   // 绿
        let (oh, os, ob) = (0.07, 0.6, 0.82)   // 橙
        let (rh, rs, rb) = (0.0, 0.62, 0.82)   // 红
        if p < 0.7 {
            return Color(hue: gh, saturation: gs, brightness: gb)
        } else if p < 0.9 {
            let t = (p - 0.7) / 0.2
            return Color(hue: lerp(gh, oh, t), saturation: lerp(gs, os, t), brightness: lerp(gb, ob, t))
        } else {
            let t = min(1, (p - 0.9) / 0.1)
            return Color(hue: lerp(oh, rh, t), saturation: lerp(os, rs, t), brightness: lerp(ob, rb, t))
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func countdownText(_ reset: Date, now: Date, label: String) -> String {
        let interval = Int(reset.timeIntervalSince(now))
        if interval <= 0 { return "已重置" }
        let days = interval / 86400
        let hours = (interval % 86400) / 3600
        let minutes = (interval % 3600) / 60
        if label == "7天" {
            return "\(days)天\(hours)小时后重置"
        }
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))分钟后重置"
        }
        return "\(minutes)分钟后重置"
    }
}
