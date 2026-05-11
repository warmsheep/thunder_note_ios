import SwiftUI
import UIKit

/// D2-I2-14 富文本编辑器底层：把 `UITextView` 包成 SwiftUI `View`，
/// 同时把光标 / 选区 (`selectedRange`) 双向绑回 SwiftUI 端，让上层 ViewModel
/// 可以基于「当前选中文本」执行 `insertToken("**","**")` 这类 Markdown 操作。
///
/// 与 SwiftUI 自带 `TextEditor` 的差异：
/// - `TextEditor` 在 iOS 18 之前没有公开的 `selection` API，无法实现「围绕选区
///   插入粗体 / 斜体」「行首插入引用 / 待办」等 Android 等价行为。
/// - 因此用 `UIViewRepresentable` 直接包 `UITextView`，与 D2-I3-08 / D2-I3-11
///   的 UIKit 包装风格一致。
struct RichTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    /// 仅用于初次出现时弹起键盘；后续聚焦由用户控制。
    let initiallyFocused: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.text = text
        textView.selectedRange = clampRange(selectedRange, in: text)
        textView.accessibilityIdentifier = "quickCaptureRichTextEditor"
        if initiallyFocused {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // text 与 selection 都是单向源（SwiftUI 端为权威），
        // 但 textViewDidChange 触发的 binding 写回会反过来再 updateUIView，
        // 这里只在内容真不一致时同步 UIKit 端，避免光标抖动。
        if uiView.text != text {
            uiView.text = text
        }
        let target = clampRange(selectedRange, in: text)
        if uiView.selectedRange != target {
            uiView.selectedRange = target
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: RichTextEditor

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // SwiftUI 在每次 setText 后会再触发 selection 变化，按需写回。
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange
            }
        }
    }

    /// 把任意外部传入的 `NSRange` clamp 到当前 text 范围内，避免越界 crash。
    private func clampRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = max(0, min(range.location, length))
        let upper = max(location, min(range.location + range.length, length))
        return NSRange(location: location, length: upper - location)
    }
}
