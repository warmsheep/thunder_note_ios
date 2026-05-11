import Foundation
import AVFoundation

/// `D2-I3-10` 视频压缩 / remux：与 Android `VideoCompressor` 等价。
///
/// - 文件 ≤ 5 MB 直接返回原 URL；
/// - 文件 > 5 MB 用 `AVAssetExportSession` 走 passthrough preset 重新封装；
/// - 仅当产物比原文件小才返回新 URL，否则保留原文件。
public enum VideoCompressor {
    public static let thresholdBytes: Int64 = 5 * 1024 * 1024

    public enum CompressError: Error, Equatable {
        case sessionCreationFailed
        case exportFailed(message: String)
    }

    /// 返回应该用来上传的最终 URL（可能等于原 URL）。
    public static func compressIfNeeded(at url: URL) async throws -> URL {
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard originalSize > thresholdBytes else { return url }

        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw CompressError.sessionCreationFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-vid-\(UUID().uuidString).mp4")
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        switch session.status {
        case .completed:
            let newSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? Int64.max
            if newSize > 0 && newSize < originalSize {
                return outputURL
            }
            // 没变小：丢弃新文件，使用原文件
            try? FileManager.default.removeItem(at: outputURL)
            return url
        case .failed, .cancelled:
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressError.exportFailed(message: session.error?.localizedDescription ?? "导出失败")
        default:
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressError.exportFailed(message: "未知导出状态")
        }
    }
}
