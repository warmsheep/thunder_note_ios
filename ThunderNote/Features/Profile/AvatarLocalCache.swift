import Foundation
import UIKit

/// D2-I6-04 头像本地缓存。
///
/// 路径：`Library/Caches/avatar.jpg`，与 Android `clearAvatarCache` 等价。
/// 用途：图片头像上传成功后立即把裁剪后的 JPEG 写到本地，UI 不必等下次 fetch；
/// 登出时由 `AuthSession` onSignOut 流程 `clear()`。
public enum AvatarLocalCache {
    public static let filename = "avatar.jpg"

    public static var fileURL: URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent(filename)
    }

    @discardableResult
    public static func persist(jpegData: Data) -> Bool {
        guard let url = fileURL else { return false }
        do {
            try jpegData.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func loadImage() -> UIImage? {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    public static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
