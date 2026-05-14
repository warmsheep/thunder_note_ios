import SwiftUI

/// 公共媒体预览 sheet：按 `MediaPreviewKind` 路由到对应视图。
struct MediaPreviewView: View {
    @StateObject var viewModel: MediaDownloadViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var presentShareSheet = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.request.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            presentShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(resolvedURL == nil)
                        .accessibilityIdentifier("mediaPreviewShareButton")
                    }
                }
                .task { await viewModel.load() }
                .sheet(isPresented: $presentShareSheet) {
                    if let resolvedURL {
                        MediaShareSheet(
                            url: resolvedURL,
                            kind: viewModel.request.kind,
                            fileName: viewModel.request.fileName ?? resolvedURL.lastPathComponent
                        )
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .tint(DesignTokens.Color.brandPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: DesignTokens.Spacing.medium) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(DesignTokens.Color.danger)
                Text("预览失败").font(DesignTokens.Typography.title)
                Text(message)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                Button("重试") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Color.brandPrimary)
            }
            .padding(DesignTokens.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let url):
            readyContent(for: url)
        }
    }

    @ViewBuilder
    private func readyContent(for url: URL) -> some View {
        switch viewModel.request.kind {
        case .image:
            ImageLightboxView(
                imageURL: url,
                onClose: { dismiss() },
                onShare: { presentShareSheet = true }
            )
        case .video:
            VideoPlayerView(url: url)
                .ignoresSafeArea(edges: .bottom)
        case .pdf:
            PDFPreviewView(url: url)
        case .textFile:
            TextFilePreviewView(url: url, fileName: viewModel.request.fileName)
        case .other:
            QLPreviewWrapper(url: url)
        }
    }

    private var resolvedURL: URL? {
        if case .ready(let url) = viewModel.state { return url }
        return nil
    }
}
