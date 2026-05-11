import SwiftUI

/// 顶部 banner：告诉用户「有 N 条刚从系统分享进来的条目待处理」。
/// 点击后会把 inbox 最顶的一条弹出 `ShareTargetPickerSheet`，用户逐条确认 / 跳过。
struct ShareInboxBannerView: View {
    let pendingCount: Int
    let onTap: () -> Void

    var body: some View {
        if pendingCount > 0 {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("收到 \(pendingCount) 条分享待处理")
                        .font(DesignTokens.Typography.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(DesignTokens.Color.brandPrimary)
            }
            .accessibilityIdentifier("shareInboxBanner")
        }
    }
}
