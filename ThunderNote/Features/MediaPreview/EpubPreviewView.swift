import SwiftUI
import WebKit
import ZIPFoundation

struct EpubPreviewView: View {
    let url: URL
    let fileName: String?

    @State private var state: LoadState = .loading
    @State private var reloadToken = UUID()

    var body: some View {
        content
            .task(id: reloadToken) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("正在打开 EPUB…")
                .tint(DesignTokens.Color.brandPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let htmlURL, let readAccessURL):
            EpubWebView(url: htmlURL, readAccessURL: readAccessURL)
        case .failed(let message):
            VStack(spacing: DesignTokens.Spacing.medium) {
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                Text("EPUB 无法预览")
                    .font(DesignTokens.Typography.title)
                Text(message)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .multilineTextAlignment(.center)
                Button("重试") { reloadToken = UUID() }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.Color.brandPrimary)
            }
            .padding(DesignTokens.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            let epubURL = url
            let document = try await Task.detached(priority: .userInitiated) {
                try EpubDocument.prepare(epubURL: epubURL)
            }.value
            state = .ready(htmlURL: document.htmlURL, readAccessURL: document.readAccessURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private enum LoadState: Equatable {
        case loading
        case ready(htmlURL: URL, readAccessURL: URL)
        case failed(String)
    }
}

private struct EpubWebView: UIViewRepresentable {
    let url: URL
    let readAccessURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = false
            if let scheme = navigationAction.request.url?.scheme?.lowercased(), scheme == "file" || scheme == "about" {
                decisionHandler(.allow, preferences)
            } else {
                decisionHandler(.cancel, preferences)
            }
        }
    }
}

enum EpubDocumentError: LocalizedError, Equatable {
    case invalidArchive
    case missingContainer
    case missingPackageDocument
    case missingSpine
    case missingHtmlContent
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "文件不是有效的 EPUB 压缩包"
        case .missingContainer:
            return "EPUB 缺少 META-INF/container.xml"
        case .missingPackageDocument:
            return "EPUB 缺少 OPF 包描述文件"
        case .missingSpine:
            return "EPUB 缺少正文目录"
        case .missingHtmlContent:
            return "EPUB 未找到可显示的正文内容"
        case .unsafePath:
            return "EPUB 内包含不安全路径，已阻止打开"
        }
    }
}

struct EpubPreparedDocument: Equatable {
    let htmlURL: URL
    let readAccessURL: URL
}

enum EpubDocument {
    static func prepare(epubURL: URL, fileManager: FileManager = .default) throws -> EpubPreparedDocument {
        let archive: Archive
        do {
            archive = try Archive(url: epubURL, accessMode: .read)
        } catch {
            throw EpubDocumentError.invalidArchive
        }
        let root = try extractionRoot(for: epubURL, fileManager: fileManager)
        try? fileManager.removeItem(at: root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try extractArchive(archive, to: root, fileManager: fileManager)

        let containerURL = root.appendingPathComponent("META-INF/container.xml")
        guard fileManager.fileExists(atPath: containerURL.path) else {
            throw EpubDocumentError.missingContainer
        }
        let containerXML = try String(contentsOf: containerURL, encoding: .utf8)
        guard let opfPath = firstMatch(in: containerXML, pattern: #"full-path\s*=\s*["']([^"']+)["']"#) else {
            throw EpubDocumentError.missingPackageDocument
        }
        let opfURL = try safeURL(root: root, relativePath: opfPath, fileManager: fileManager)
        let opfBaseURL = opfURL.deletingLastPathComponent()
        let opfXML = try String(contentsOf: opfURL, encoding: .utf8)
        let manifest = manifestItems(from: opfXML)
        let spine = spineItemRefs(from: opfXML)
        guard !spine.isEmpty else { throw EpubDocumentError.missingSpine }

        let ordered = spine.compactMap { manifest[$0] }
        let htmlItems = ordered.filter { item in
            let mediaType = item.mediaType.lowercased()
            let href = item.href.lowercased()
            return mediaType.contains("html") || href.hasSuffix(".html") || href.hasSuffix(".xhtml") || href.hasSuffix(".htm")
        }
        guard !htmlItems.isEmpty else { throw EpubDocumentError.missingHtmlContent }

        let html = try buildReaderHTML(items: htmlItems, opfBaseURL: opfBaseURL, root: root, fileManager: fileManager)
        let htmlURL = root.appendingPathComponent("tn_epub_reader.html")
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        return EpubPreparedDocument(htmlURL: htmlURL, readAccessURL: root)
    }

    private static func extractionRoot(for epubURL: URL, fileManager: FileManager) throws -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let hash = simpleHash(epubURL.path)
        return caches.appendingPathComponent("tn.epub", isDirectory: true).appendingPathComponent(hash, isDirectory: true)
    }

    private static func extractArchive(_ archive: Archive, to root: URL, fileManager: FileManager) throws {
        for entry in archive {
            let destination = try safeURL(root: root, relativePath: entry.path, fileManager: fileManager)
            if entry.type == .directory {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: destination)
        }
    }

    private static func safeURL(root: URL, relativePath: String, fileManager: FileManager) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") || normalized.contains("://") || normalized.contains("../") || normalized == ".." || normalized.hasPrefix("..") {
            throw EpubDocumentError.unsafePath(relativePath)
        }
        let destination = root.appendingPathComponent(normalized).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard destination.path == rootPath || destination.path.hasPrefix(rootPath + "/") else {
            throw EpubDocumentError.unsafePath(relativePath)
        }
        return destination
    }

    private static func resolvedURL(root: URL, base: URL, relativePath: String) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") || normalized.contains("://") {
            throw EpubDocumentError.unsafePath(relativePath)
        }
        let destination = base.appendingPathComponent(normalized).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard destination.path == rootPath || destination.path.hasPrefix(rootPath + "/") else {
            throw EpubDocumentError.unsafePath(relativePath)
        }
        return destination
    }

    private static func manifestItems(from xml: String) -> [String: ManifestItem] {
        let pattern = #"<item\b([^>]*)>"#
        return matches(in: xml, pattern: pattern).reduce(into: [String: ManifestItem]()) { result, attributes in
            guard let id = attribute("id", in: attributes), let href = attribute("href", in: attributes) else { return }
            result[id] = ManifestItem(href: href, mediaType: attribute("media-type", in: attributes) ?? "")
        }
    }

    private static func spineItemRefs(from xml: String) -> [String] {
        let pattern = #"<itemref\b([^>]*)>"#
        return matches(in: xml, pattern: pattern).compactMap { attribute("idref", in: $0) }
    }

    private static func buildReaderHTML(items: [ManifestItem], opfBaseURL: URL, root: URL, fileManager: FileManager) throws -> String {
        var sections: [String] = []
        for item in items {
            let decodedHref = item.href.removingPercentEncoding ?? item.href
            let itemURL = try resolvedURL(root: root, base: opfBaseURL, relativePath: decodedHref)
            guard fileManager.fileExists(atPath: itemURL.path) else { continue }
            let raw = try String(contentsOf: itemURL, encoding: .utf8)
            let body = firstMatch(in: raw, pattern: #"(?is)<body[^>]*>(.*?)</body>"#) ?? raw
            let rewritten = rewriteReferences(in: body, base: itemURL.deletingLastPathComponent(), root: root)
            sections.append("<section>\(rewritten)</section>")
        }
        guard !sections.isEmpty else { throw EpubDocumentError.missingHtmlContent }
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
          <style>
            body { margin: 0; padding: 20px; font: -apple-system-body; line-height: 1.65; color: #1f2937; background: #ffffff; }
            img, svg, video { max-width: 100%; height: auto; }
            section { margin: 0 auto 28px auto; max-width: 760px; }
            a { color: #2563eb; }
            pre { white-space: pre-wrap; overflow-wrap: anywhere; }
          </style>
        </head>
        <body>
        \(sections.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let group = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[group])
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        matches(in: text, pattern: pattern).first
    }

    private static func attribute(_ name: String, in text: String) -> String? {
        firstMatch(in: text, pattern: #"\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*["']([^"']*)["']"#)
    }

    private static func rewriteReferences(in html: String, base: URL, root: URL) -> String {
        let pattern = #"\b(src|href)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return html }
        var output = html
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        for match in matches.reversed() {
            guard match.numberOfRanges == 3,
                  let fullRange = Range(match.range(at: 0), in: output),
                  let keyRange = Range(match.range(at: 1), in: html),
                  let valueRange = Range(match.range(at: 2), in: html) else { continue }
            let key = String(html[keyRange])
            let value = String(html[valueRange])
            let lowercased = value.lowercased()
            if value.hasPrefix("#") || lowercased.hasPrefix("data:") {
                continue
            }
            guard let url = try? resolvedURL(root: root, base: base, relativePath: value.removingPercentEncoding ?? value) else {
                output.replaceSubrange(fullRange, with: "")
                continue
            }
            output.replaceSubrange(fullRange, with: #"\#(key)="\#(escapeHTML(url.absoluteString))""#)
        }
        return output
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func simpleHash(_ input: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private struct ManifestItem: Equatable {
        let href: String
        let mediaType: String
    }
}
