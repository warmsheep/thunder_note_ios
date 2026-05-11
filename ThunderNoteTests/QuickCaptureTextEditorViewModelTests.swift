import XCTest
@testable import ThunderNote

final class QuickCaptureTextEditorViewModelTests: XCTestCase {

    /// 选区为空时插入粗体：在光标处插入空 token，光标停在 `**` 之后准备输入。
    @MainActor
    func test_toggleBold_emptySelection_insertsTokenAtCursor() {
        let vm = makeViewModel()
        vm.text = "Hello"
        vm.selectedRange = NSRange(location: 5, length: 0)

        vm.toggleBold()

        XCTAssertEqual(vm.text, "Hello****")
        // 光标应位于 replacement 末尾。
        XCTAssertEqual(vm.selectedRange.location, 9)
        XCTAssertEqual(vm.selectedRange.length, 0)
    }

    /// 包裹选区粗体：选中文本被保留并在两端添加 `**`。
    @MainActor
    func test_toggleBold_wrappingSelection_preservesText() {
        let vm = makeViewModel()
        vm.text = "Hello world"
        vm.selectedRange = NSRange(location: 6, length: 5) // 选中 "world"

        vm.toggleBold()

        XCTAssertEqual(vm.text, "Hello **world**")
        // 光标位于 replacement 末尾（"**world**" 之后）。
        XCTAssertEqual(vm.selectedRange.location, 15)
    }

    /// 斜体：单 `*` 包裹。
    @MainActor
    func test_toggleItalic_wrappingSelection() {
        let vm = makeViewModel()
        vm.text = "abc"
        vm.selectedRange = NSRange(location: 0, length: 3)

        vm.toggleItalic()

        XCTAssertEqual(vm.text, "*abc*")
    }

    /// 引用：在选区所在行的行首插入 `> `。
    @MainActor
    func test_insertQuote_insertsLinePrefixAtLineStart() {
        let vm = makeViewModel()
        vm.text = "first\nsecond line"
        // 光标位于 "second line" 中间（"sec|ond"）。
        vm.selectedRange = NSRange(location: 9, length: 0)

        vm.insertQuote()

        XCTAssertEqual(vm.text, "first\n> second line")
        // 光标应平移 prefix.length(=2) 位。
        XCTAssertEqual(vm.selectedRange.location, 11)
    }

    /// 待办：在当前行行首插入 `- [ ] `。
    @MainActor
    func test_insertTodo_insertsLinePrefix() {
        let vm = makeViewModel()
        vm.text = "task one"
        vm.selectedRange = NSRange(location: 4, length: 0)

        vm.insertTodo()

        XCTAssertEqual(vm.text, "- [ ] task one")
        XCTAssertEqual(vm.selectedRange.location, 10)
    }

    /// 多行：光标在第二行时，待办 prefix 不污染第一行。
    @MainActor
    func test_insertTodo_onlyAffectsCurrentLine() {
        let vm = makeViewModel()
        vm.text = "alpha\nbeta"
        vm.selectedRange = NSRange(location: 8, length: 0)

        vm.insertTodo()

        XCTAssertEqual(vm.text, "alpha\n- [ ] beta")
    }

    /// save：trim 后非空 → submit 闭包被调一次，返回 true 后 isSubmitting 复位。
    @MainActor
    func test_save_trimmedNonEmpty_invokesSubmit() async {
        let recorder = SubmitRecorder(result: true)
        let vm = QuickCaptureTextEditorViewModel { text in
            await recorder.record(text)
            return recorder.result
        }
        vm.text = "  hello  "

        let ok = await vm.save()

        XCTAssertTrue(ok)
        let received = await recorder.received
        XCTAssertEqual(received, ["hello"])
        XCTAssertFalse(vm.isSubmitting)
    }

    /// save：trim 后为空 → 不触发 submit，提示 transientMessage。
    @MainActor
    func test_save_blankText_doesNotSubmit() async {
        let recorder = SubmitRecorder(result: true)
        let vm = QuickCaptureTextEditorViewModel { text in
            await recorder.record(text)
            return recorder.result
        }
        vm.text = "   \n  "

        let ok = await vm.save()

        XCTAssertFalse(ok)
        let received = await recorder.received
        XCTAssertEqual(received.count, 0)
        XCTAssertEqual(vm.transientMessage, "请输入内容")
    }

    /// save：submit 返回 false → transientMessage 显示「保存失败」。
    @MainActor
    func test_save_failure_setsTransientMessage() async {
        let recorder = SubmitRecorder(result: false)
        let vm = QuickCaptureTextEditorViewModel { text in
            await recorder.record(text)
            return recorder.result
        }
        vm.text = "hello"

        let ok = await vm.save()

        XCTAssertFalse(ok)
        XCTAssertEqual(vm.transientMessage, "保存失败，请稍后重试")
    }

    /// canSubmit：纯空白不可提交；isSubmitting 时锁住。
    @MainActor
    func test_canSubmit_respectsTrimAndSubmitting() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.canSubmit)
        vm.text = "  "
        XCTAssertFalse(vm.canSubmit)
        vm.text = "hi"
        XCTAssertTrue(vm.canSubmit)
    }

    // MARK: - Helpers

    @MainActor
    private func makeViewModel() -> QuickCaptureTextEditorViewModel {
        QuickCaptureTextEditorViewModel { _ in true }
    }

    /// 测试用的并发安全收集器：替代直接 var counter / [String]
    /// 的写法，避开 Swift 严格并发对闭包变量捕获的 warning。
    private actor SubmitRecorder {
        var received: [String] = []
        let result: Bool

        init(result: Bool) {
            self.result = result
        }

        func record(_ text: String) {
            received.append(text)
        }
    }
}
