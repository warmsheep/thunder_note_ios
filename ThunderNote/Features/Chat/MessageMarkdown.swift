import Foundation
import SwiftUI

/// 消息正文 Markdown 渲染。与 Android `MarkdownRenderer.looksLikeMarkdown`
/// 的启发式规则等价：只有文本中疑似 Markdown 时才走渲染，否则当纯文本展示，
/// 避免空格 / 连字符等被误识别。
public enum MessageMarkdown {
    public static func looksLikeMarkdown(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        // 任一 Markdown 标志命中即可：粗体/斜体/代码/行内代码/链接/列表/标题/引用
        let patterns: [String] = [
            #"\*\*[^*]+\*\*"#,             // **bold**
            #"(?<!\*)\*[^*]+\*(?!\*)"#,    // *italic*
            #"`[^`]+`"#,                     // inline code
            #"```"#,                          // fenced code
            #"\[[^\]]+\]\([^)]+\)"#,        // [text](url)
            #"^#{1,6} "#,                    // # heading
            #"^[-+*] "#,                      // bullet list
            #"^> "#,                          // quote
            #"^\d+\. "#                      // numbered list
        ]
        for pattern in patterns {
            if text.range(of: pattern, options: [.regularExpression, .anchored]) != nil { return true }
            if text.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }

    /// iOS 17 系统 `AttributedString(markdown:)` 已支持基础语法；这里只做封装。
    /// 失败时回退为纯文本。
    public static func render(_ text: String) -> AttributedString {
        if looksLikeMarkdown(text),
           let attr = try? AttributedString(
               markdown: text,
               options: AttributedString.MarkdownParsingOptions(
                   allowsExtendedAttributes: false,
                   interpretedSyntax: .inlineOnlyPreservingWhitespace
               )
           ) {
            return attr
        }
        return AttributedString(text)
    }
}
