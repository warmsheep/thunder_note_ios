import SwiftUI
import UniformTypeIdentifiers

/// D2-I6-15 调试日志查看页
@MainActor
public struct DebugLogView: View {
    @ObservedObject var debugLog = DebugLog.shared

    @State private var selectedTab: Int = 0 // 0: 当前, 1: 上次
    @State private var showingClearConfirm = false
    @State private var isSharing = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Session", selection: $selectedTab) {
                Text("当前会话").tag(0)
                Text("上次会话").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                Text(selectedTab == 0 ? debugLog.currentLogText : debugLog.previousLogText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .navigationTitle("调试日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { GestureLockBypass.register(); isSharing = true }) {
                        Label("分享导出", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive, action: { showingClearConfirm = true }) {
                        Label("清空日志", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("确定要清空所有日志吗？", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                debugLog.clearAll()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: [selectedTab == 0 ? debugLog.getCurrentLogURL() : debugLog.getPreviousLogURL()])
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
