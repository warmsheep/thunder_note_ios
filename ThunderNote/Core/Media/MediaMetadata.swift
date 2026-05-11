import Foundation
import AVFoundation
import UIKit

/// 媒体元数据 / 缩略图 / 压缩 工具集。
public enum MediaMetadata {
    /// 解析视频时长（秒，向上取整）。与 Android `MediaMetadataRetriever` 等价。
    public static func videoDurationSeconds(at url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        do {
            let cmTime = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(cmTime)
            guard seconds.isFinite, seconds > 0 else { return nil }
            return Int(seconds.rounded(.up))
        } catch {
            return nil
        }
    }

    /// 截取视频首帧 thumbnail。
    public static func videoThumbnail(at url: URL, maxSize: CGFloat = 512) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        do {
            // 取 0.1s 处的 frame，避开纯黑首帧。
            let cmTime = CMTime(seconds: 0.1, preferredTimescale: 600)
            let cgImage = try await generator.image(at: cmTime).image
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

/// 静态图片缩略图。
public enum ImageThumbnailRenderer {
    /// 把任意 URL 指向的图片解码为 maxSize（默认 512px）的 JPEG Data。
    /// 用于上传缩略图 / 本地预览。
    public static func renderJPEG(
        from url: URL,
        maxSize: CGFloat = 512,
        quality: CGFloat = 0.78
    ) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // 使用固定 2x 像素密度，避免 `UIScreen.main` 在 Swift 6 严格并发下要求 MainActor。
        // 缩略图本就是低分辨率视觉，固定 2x 完全够用。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize * 2
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cg)
        return image.jpegData(compressionQuality: quality)
    }
}
