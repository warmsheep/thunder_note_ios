import SwiftUI

/// D2-I3-11 实时波形显示：把 ChatRecordingHelper.levels（0~1 数组）画成一排立柱。
/// - 立柱数量与 `levels.count` 同步，最右侧最新。
/// - 颜色随 isCancelArea 切换（取消区域时红色提示）。
struct VoiceWaveView: View {
    let levels: [Float]
    let isCancelArea: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(levels.count, 1)
            let columnWidth = max(2, (width - CGFloat(count - 1) * 2) / CGFloat(count))
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(barColor)
                        .frame(
                            width: columnWidth,
                            height: max(4, CGFloat(level) * height)
                        )
                }
            }
            .frame(width: width, height: height, alignment: .center)
        }
    }

    private var barColor: Color {
        if isCancelArea {
            return Color.red.opacity(0.85)
        }
        return DesignTokens.Color.brandPrimary
    }
}

/// 录制中浮层（覆盖在键盘 / 输入区上方）。包含：
/// - 圆形动画指示
/// - 当前实时波形
/// - 计时：mm:ss / 60
/// - 取消区域提示文案（上滑后变色 + "松手取消"）
struct RecordingOverlay: View {
    let elapsed: TimeInterval
    let levels: [Float]
    let isCancelArea: Bool

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: isCancelArea ? "xmark.circle.fill" : "mic.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(isCancelArea ? Color.red : DesignTokens.Color.brandPrimary)
                .accessibilityIdentifier("recordingMicIcon")

            VoiceWaveView(levels: levels, isCancelArea: isCancelArea)
                .frame(height: 60)
                .padding(.horizontal, 12)

            Text(format(elapsed))
                .font(DesignTokens.Typography.body.monospacedDigit())
                .foregroundStyle(DesignTokens.Color.textPrimary)

            Text(isCancelArea ? "松手取消" : "上滑取消")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(isCancelArea ? Color.red : DesignTokens.Color.textSecondary)
        }
        .padding(DesignTokens.Spacing.large)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 10)
        .accessibilityIdentifier("recordingOverlay")
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%01d:%02d / 1:00", m, s)
    }
}
