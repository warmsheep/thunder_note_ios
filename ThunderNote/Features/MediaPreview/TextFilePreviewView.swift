import SwiftUI

struct TextFilePreviewView: View {
    let url: URL
    let fileName: String?

    @State private var text: String?
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            if let text {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if loadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignTokens.Color.danger)
                    Text("无法读取文件内容")
                        .font(DesignTokens.Typography.body)
                }
                .padding()
            } else {
                ProgressView()
                    .tint(DesignTokens.Color.brandPrimary)
                    .padding(.top, 60)
            }
        }
        .task { loadText() }
    }

    private func loadText() {
        let maxBytes = 1024 * 1024
        guard let stream = try? FileHandle(forReadingFrom: url) else {
            loadFailed = true
            return
        }
        defer { try? stream.close() }
        let data = (try? stream.read(upToCount: maxBytes)) ?? Data()
        if data.isEmpty {
            text = "（空文件）"
        } else {
            text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
                ?? "（无法解码文件内容）"
        }
    }
}
