import SwiftUI
import AVKit

struct CachedThumbnailView: View {
    let objectName: String?
    let fileRepository: FileRepository?
    let isVideo: Bool

    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var failed = false

    init(
        objectName: String?,
        fileRepository: FileRepository? = nil,
        isVideo: Bool = false
    ) {
        self.objectName = objectName
        self.fileRepository = fileRepository
        self.isVideo = isVideo
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                thumbnailPlaceholder
            }
        }
        .task(id: objectName) {
            await loadThumbnail()
        }
    }

    private var thumbnailPlaceholder: some View {
        Color.gray.opacity(0.2)
            .overlay(
                Image(systemName: isVideo ? "video.fill" : "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
            )
    }

    @MainActor
    private func loadThumbnail() async {
        guard let objectName, !objectName.isEmpty else {
            failed = true
            return
        }
        isLoading = true
        failed = false
        uiImage = nil

        if isVideo {
            await loadVideoThumbnail(objectName: objectName)
        } else {
            await loadImageThumbnail(objectName: objectName)
        }
        isLoading = false
    }

    @MainActor
    private func loadImageThumbnail(objectName: String) async {
        // FileRepository.download 已带 Bearer token 鉴权 + 磁盘缓存，不需要额外 URL fallback。
        // 直走 URLSession.shared 会指向 /api/files/download，该端点要求 token，不鉴权会 401。
        guard let repo = fileRepository,
              let img = await Self.loadImageViaRepository(repo, objectName: objectName) else {
            failed = true
            return
        }
        uiImage = img
    }

    @MainActor
    private func loadVideoThumbnail(objectName: String) async {
        guard let repo = fileRepository else {
            failed = true
            return
        }
        do {
            let localURL = try await repo.download(objectName: objectName)
            let thumbnail = await generateVideoThumbnail(from: localURL)
            if let thumbnail {
                uiImage = thumbnail
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }

    private static func loadImageViaRepository(_ repo: FileRepository, objectName: String) async -> UIImage? {
        do {
            let localURL = try await repo.download(objectName: objectName)
            if let img = UIImage(contentsOfFile: localURL.path) {
                return img
            }
            if let data = try? Data(contentsOf: localURL),
               let img = UIImage(data: data) {
                return img
            }
        } catch {}
        return nil
    }

}

private func generateVideoThumbnail(from url: URL) async -> UIImage? {
    await withCheckedContinuation { continuation in
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
            if let cgImage, result == .succeeded {
                continuation.resume(returning: UIImage(cgImage: cgImage))
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}
