import SwiftUI

/// D2-I2-13 快速捕获 FAB：右下角悬浮的圆角方形按钮。
/// - 与 Android `FloatingActionButton` 视觉对齐：圆角 16pt 矩形 + 主色背景 +
///   白色 `+` 图标。
/// - 点击触发 `onTap`，触发后做一次 0.85 倍快速缩放 + 透明度回弹动画
///   （与 Android `playCaptureAnimation` 等价）。
struct QuickCaptureFAB: View {
    let onTap: () -> Void
    @State private var pressed: Bool = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                pressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                    pressed = false
                }
            }
            onTap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(DesignTokens.Color.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .scaleEffect(pressed ? 0.86 : 1.0)
        .opacity(pressed ? 0.85 : 1.0)
        .accessibilityIdentifier("quickCaptureFAB")
    }
}
