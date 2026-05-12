import SwiftUI

/// 3x3 绘制网格，处理触摸点和节点连接。
public struct GestureLockGrid: View {
    @Binding var path: [Int]
    @Binding var isError: Bool

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let step = size / 3
            let radius: CGFloat = 8

            ZStack {
                // Draw paths
                if path.count > 1 {
                    Path { p in
                        let first = center(for: path[0], step: step)
                        p.move(to: first)
                        for i in 1..<path.count {
                            p.addLine(to: center(for: path[i], step: step))
                        }
                    }
                    .stroke(isError ? Color.red : DesignTokens.Color.brandPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                // Draw dots
                ForEach(0..<9, id: \.self) { index in
                    let isSelected = path.contains(index)
                    Circle()
                        .fill(isSelected ? (isError ? Color.red : DesignTokens.Color.brandPrimary) : Color.gray.opacity(0.3))
                        .frame(width: isSelected ? radius * 3 : radius * 2, height: isSelected ? radius * 3 : radius * 2)
                        .position(center(for: index, step: step))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isError { return }
                        if let index = nodeIndex(for: value.location, step: step), !path.contains(index) {
                            path.append(index)
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(40)
    }

    private func center(for index: Int, step: CGFloat) -> CGPoint {
        let row = CGFloat(index / 3)
        let col = CGFloat(index % 3)
        return CGPoint(x: col * step + step / 2, y: row * step + step / 2)
    }

    private func nodeIndex(for point: CGPoint, step: CGFloat) -> Int? {
        let col = Int(point.x / step)
        let row = Int(point.y / step)
        guard col >= 0 && col < 3 && row >= 0 && row < 3 else { return nil }
        
        let center = self.center(for: row * 3 + col, step: step)
        let distance = hypot(point.x - center.x, point.y - center.y)
        if distance < step / 3 {
            return row * 3 + col
        }
        return nil
    }
}
