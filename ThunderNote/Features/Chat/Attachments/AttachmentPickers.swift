import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 图片 / 视频选择状态 helper：把 `PhotosPickerItem` 的二进制 dump 到临时文件，
/// 让 `AttachmentSendingService` 走「本地文件 URL 上传」的统一路径。
///
/// `PhotosPickerItem` 在 iOS 16 SDK 没有显式声明 `Sendable`（iOS 17+ 才补上）。
/// 工具类整体标 `@unchecked Sendable` 让 Swift 严格并发对系统类型缺口静音，
/// 实际访问全部限定在主线程通过 SwiftUI（`@StateObject`）触发。
final class PhotosPickerHelper: ObservableObject, @unchecked Sendable {
    @Published var selectedItem: PhotosPickerItem? = nil

    /// 读取所选 PhotosPickerItem 的数据并写入临时文件，返回本地 URL + 建议的扩展名。
    /// 读取失败返回 nil。
    func loadLocalURL(suggestedExtension fallback: String) async -> URL? {
        guard let item = selectedItem else { return nil }
        let ext = fileExtension(for: item) ?? fallback
        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            return nil
        }
        guard let payload = data else { return nil }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("tn-picked-\(UUID().uuidString).\(ext)")
            try payload.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 清理所选项（避免用户连续选同一项不触发 onChange）。
    func reset() {
        selectedItem = nil
    }

    private func fileExtension(for item: PhotosPickerItem) -> String? {
        // PhotosPickerItem 的 UTI 映射到扩展名
        let types = item.supportedContentTypes
        for utType in types {
            if let preferred = utType.preferredFilenameExtension {
                return preferred
            }
        }
        return nil
    }
}

/// 视频选择的同款 helper（与图片区分开以便 `matching` 过滤不同 filter）。
typealias VideoPickerHelper = PhotosPickerHelper
