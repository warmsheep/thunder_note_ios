import SwiftUI
import UIKit
import Photos

/// UIActivityViewController 的 SwiftUI 封装；用户主动触发的分享 / 保存入口。
/// - 图片 / 视频：用户可以选择「保存到相册」（`PHPhotoLibrary`）或「拷贝」等活动。
/// - 其他文件：用户可以选择「保存到文件」（系统活动中的 `Save to Files`）。
struct MediaShareSheet: UIViewControllerRepresentable {
    let url: URL
    let kind: MediaPreviewKind
    let fileName: String?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // 让系统活动面板里自动识别到「保存到文件」「保存到相册」等。
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 把当前资源（URL）另存到相册 / 文件的命令式 helper。
/// 保存到相册需要 `NSPhotoLibraryAddUsageDescription` 权限（D2-I0-07 已声明）。
public enum MediaShareHelper {
    public enum SaveError: Error, Equatable {
        case permissionDenied
        case unsupportedKind
        case failed(message: String)
    }

    /// 把 image / video 文件保存到系统相册。
    public static func saveToPhotos(url: URL, kind: MediaPreviewKind) async throws {
        guard kind == .image || kind == .video else { throw SaveError.unsupportedKind }
        let status = await requestPhotoAddAuthorization()
        guard status == .authorized || status == .limited else {
            throw SaveError.permissionDenied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                switch kind {
                case .image:
                    PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url)
                case .video:
                    PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
                default: break
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.failed(message: error?.localizedDescription ?? "保存到相册失败"))
                }
            }
        }
    }

    private static func requestPhotoAddAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
