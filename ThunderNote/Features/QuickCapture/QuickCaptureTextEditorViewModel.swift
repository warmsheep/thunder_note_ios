import Foundation

/// D2-I2-14 全屏快速捕获文本编辑器 ViewModel。
/// 负责：
/// - 维护正文 `text` 与当前 `selectedRange`（与 `RichTextEditor` 双向绑定）。
/// - 实现 4 个富文本快捷键的 Markdown 插入：粗体 / 斜体 / 引用 / 待办。
/// - 调度保存逻辑，把内容直接写到收集箱（`flashNoteId = -1`）。
///
/// 与 Android `QuickCaptureTextFragment` 行为对齐：
/// - 粗体 / 斜体走「围绕选区两端插入 token」（与 Android `insertToken`）。
/// - 引用 / 待办走「在选区所在行的行首插入前缀」（与 Android `insertLinePrefix`）。
@MainActor
public final class QuickCaptureTextEditorViewModel: ObservableObject {
    @Published public var text: String = ""
    @Published public var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @Published public private(set) var isSubmitting: Bool = false
    @Published public var transientMessage: String? = nil

    /// 上层注入的发送闭包：返回 `true` 表示成功（含远端写入 + 本地预览刷新）。
    /// 由 `AppDependencies.submitQuickCaptureText(_:)` 提供。
    private let submit: @MainActor (String) async -> Bool

    public init(submit: @escaping @MainActor (String) async -> Bool) {
        self.submit = submit
    }

    public var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    /// 粗体 → `**...**`。
    public func toggleBold() {
        insertToken(prefix: "**", suffix: "**")
    }

    /// 斜体 → `*...*`。
    public func toggleItalic() {
        insertToken(prefix: "*", suffix: "*")
    }

    /// 引用 → 在选区所在行行首插入 `> `。
    public func insertQuote() {
        insertLinePrefix("> ")
    }

    /// 待办 → 在选区所在行行首插入 `- [ ] `。
    public func insertTodo() {
        insertLinePrefix("- [ ] ")
    }

    /// 保存：trim 后非空才走 submit；上层闭包负责实际网络写入。
    /// - Returns: 是否保存成功（用于 View 层决定是否 dismiss）。
    public func save() async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            transientMessage = "请输入内容"
            return false
        }
        if isSubmitting { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await submit(trimmed)
        if !ok {
            transientMessage = "保存失败，请稍后重试"
        }
        return ok
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    // MARK: - 富文本工具

    /// 围绕当前选区前后插入 `prefix` / `suffix`；选中文本被保留在中间。
    /// 选区为空时退化为「插入空 token，光标停在中间」（与 Android 行为一致）。
    func insertToken(prefix: String, suffix: String) {
        let nsString = text as NSString
        let safe = clampRange(selectedRange, length: nsString.length)
        let selected = nsString.substring(with: safe)
        let replacement = prefix + selected + suffix
        let updated = nsString.replacingCharacters(in: safe, with: replacement) as String
        text = updated
        // 与 Android 等价：把光标放到 replacement 末尾。
        let nextLocation = safe.location + (replacement as NSString).length
        let clampedLocation = min(nextLocation, (updated as NSString).length)
        selectedRange = NSRange(location: clampedLocation, length: 0)
    }

    /// 在选区所在行的行首插入 `prefix`；当前光标位置随之向后位移 prefix 长度。
    func insertLinePrefix(_ prefix: String) {
        let nsString = text as NSString
        let safe = clampRange(selectedRange, length: nsString.length)
        // 找到 selectedRange.location 所在行的行首：往前回溯到上一个换行符之后。
        var lineStart = safe.location
        while lineStart > 0 && nsString.character(at: lineStart - 1) != UInt16(10) {
            lineStart -= 1
        }
        let prefixNS = prefix as NSString
        let inserted = nsString.replacingCharacters(
            in: NSRange(location: lineStart, length: 0),
            with: prefix
        ) as String
        text = inserted
        // 光标跟随原选区起点平移一个 prefix.length。
        let newLocation = min(safe.location + prefixNS.length, (inserted as NSString).length)
        selectedRange = NSRange(location: newLocation, length: 0)
    }

    private func clampRange(_ range: NSRange, length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let upper = max(location, min(range.location + range.length, length))
        return NSRange(location: location, length: upper - location)
    }
}
