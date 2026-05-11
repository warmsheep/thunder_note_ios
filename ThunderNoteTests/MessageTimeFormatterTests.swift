import XCTest
@testable import ThunderNote

final class MessageTimeFormatterTests: XCTestCase {
    func test_parse_handlesIsoAndLocalDateTime() {
        XCTAssertNotNil(MessageTimeFormatter.parse("2026-05-11T10:00:00Z"))
        XCTAssertNotNil(MessageTimeFormatter.parse("2026-05-11T10:00:00"))
        XCTAssertNotNil(MessageTimeFormatter.parse("2026-05-11T10:00:00.123"))
        XCTAssertNil(MessageTimeFormatter.parse(nil))
        XCTAssertNil(MessageTimeFormatter.parse(""))
    }

    func test_shouldShowSeparator_returnsTrueForFirstAndOver5Min() {
        XCTAssertTrue(MessageTimeFormatter.shouldShowSeparator(previous: nil, current: Date()))

        let now = Date()
        let sixMinAgo = now.addingTimeInterval(-6 * 60)
        XCTAssertTrue(MessageTimeFormatter.shouldShowSeparator(previous: sixMinAgo, current: now))

        let oneMinAgo = now.addingTimeInterval(-60)
        XCTAssertFalse(MessageTimeFormatter.shouldShowSeparator(previous: oneMinAgo, current: now))
    }

    func test_shouldShowSeparator_returnsFalseWhenCurrentNil() {
        XCTAssertFalse(MessageTimeFormatter.shouldShowSeparator(previous: Date(), current: nil))
    }
}

final class MessageMarkdownTests: XCTestCase {
    func test_looksLikeMarkdown_detectsCommonPatterns() {
        XCTAssertTrue(MessageMarkdown.looksLikeMarkdown("**bold**"))
        XCTAssertTrue(MessageMarkdown.looksLikeMarkdown("*italic*"))
        XCTAssertTrue(MessageMarkdown.looksLikeMarkdown("`code`"))
        XCTAssertTrue(MessageMarkdown.looksLikeMarkdown("[link](https://example.com)"))
        XCTAssertTrue(MessageMarkdown.looksLikeMarkdown("# heading"))
        XCTAssertTrue(MessageMarkdown.looksLikeMarkdown("- bullet"))
        XCTAssertTrue(MessageMarkdown.looksLikeMarkdown("> quote"))
    }

    func test_looksLikeMarkdown_falseForPlainText() {
        XCTAssertFalse(MessageMarkdown.looksLikeMarkdown("纯文本消息"))
        XCTAssertFalse(MessageMarkdown.looksLikeMarkdown("hello world"))
        XCTAssertFalse(MessageMarkdown.looksLikeMarkdown(""))
    }

    func test_render_returnsAttributedStringWithoutCrash() {
        let plain = MessageMarkdown.render("hello")
        XCTAssertEqual(String(plain.characters), "hello")

        let bold = MessageMarkdown.render("**bold**")
        XCTAssertFalse(String(bold.characters).contains("**"), "Markdown 渲染应剥离星号")
    }
}
