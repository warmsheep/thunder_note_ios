import Foundation

/// 媒体预览前置下载：把 objectName 解析为本地 URL（命中缓存直接复用）。
@MainActor
public final class MediaDownloadViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case ready(URL)
        case failed(String)
    }

    @Published public private(set) var state: LoadState = .idle

    public let request: MediaPreviewRequest
    private let fileRepository: FileRepository

    public init(request: MediaPreviewRequest, fileRepository: FileRepository) {
        self.request = request
        self.fileRepository = fileRepository
    }

    public func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            let localURL = try await fileRepository.download(objectName: request.objectName)
            state = .ready(localURL)
        } catch let err as FileRepositoryError {
            state = .failed(errorMessage(for: err))
        } catch let api as APIError {
            state = .failed(api.displayMessage)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func errorMessage(for error: FileRepositoryError) -> String {
        switch error {
        case .fileNotFound: return "文件不存在"
        case .unsupportedScheme: return "无效的下载地址"
        case .invalidResponse: return "服务器返回异常"
        case .http(let status): return "下载失败（HTTP \(status)）"
        case .transport(let message): return message
        }
    }
}
