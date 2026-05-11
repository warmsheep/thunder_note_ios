import SwiftUI
import UIKit
import AVFoundation

/// D2-I3-08 相机拍照入口：UIKit `UIImagePickerController` 的 SwiftUI 包装。
/// - 仅做拍照（mediaTypes 为 image），不录视频；视频走 `PhotosPicker(matching:.videos)`。
/// - 拍完照写到 tmp 目录并通过 `onPicked(localURL:)` 回调；调用方拿到 URL 后走
///   `AttachmentSendingService.uploadImage` 上传链路。
/// - 需要的权限：`NSCameraUsageDescription`（已在 project.yml 声明）。
struct CameraCaptureView: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (URL) -> Void
        let onCancel: () -> Void

        init(onPicked: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            guard let image = (info[.originalImage] as? UIImage) ?? (info[.editedImage] as? UIImage) else {
                onCancel()
                return
            }
            // JPEG 78% 质量；原图通常 1~3MB，后续上传会 stream 到 multipart。
            guard let data = image.jpegData(compressionQuality: 0.78) else {
                onCancel()
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("tn-camera-\(UUID().uuidString).jpg")
            do {
                try data.write(to: url, options: .atomic)
                onPicked(url)
            } catch {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCancel()
        }
    }

    /// 检查相机硬件是否可用（模拟器没有相机，需要在调用方判断后才弹出 sheet）。
    public static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}
