import UIKit
import UniformTypeIdentifiers

/// Share Extension：收集系统分享进来的 text / image / video / file 并写入 ShareInbox，
/// 等主 App 启动后再由 `ShareInboxConsumer` 统一消费。
/// 真正跨进程工作需要把 App Group entitlement（`group.com.flashnote.ios`）同时打开
/// 在主 App 与该扩展上，目前阶段未启用 entitlement，仅完成代码通路。
final class ShareViewController: UIViewController {
    private let progressView = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        progressView.startAnimating()
        Task { await ingestAndComplete() }
    }

    // MARK: - UI

    private func setupUI() {
        statusLabel.text = "正在保存到闪记收件箱…"
        statusLabel.font = .systemFont(ofSize: 16)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [progressView, statusLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    // MARK: - 收集 + 写入

    private func ingestAndComplete() async {
        let entries = await collectEntries()
        if entries.isEmpty {
            finish(success: false, message: "未能解析到可分享内容")
            return
        }
        guard let store = ShareInboxStore() else {
            finish(success: false, message: "无法创建 ShareInbox 存储")
            return
        }
        for entry in entries {
            do {
                try store.append(entry)
            } catch {
                // 单条失败不阻断批量，记录后续再看。
            }
        }
        finish(success: true, message: "已保存 \(entries.count) 条到闪记")
    }

    private func collectEntries() async -> [ShareInboxEntry] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
        var entries: [ShareInboxEntry] = []
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if let entry = await readAttachment(provider) {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    private func readAttachment(_ provider: NSItemProvider) async -> ShareInboxEntry? {
        // 按优先级尝试几种 UTI。
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await readFile(provider, typeIdentifier: UTType.movie.identifier, kind: .video)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await readFile(provider, typeIdentifier: UTType.image.identifier, kind: .image)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await readText(provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await readText(provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            return await readFile(provider, typeIdentifier: UTType.data.identifier, kind: .file)
        }
        return nil
    }

    private func readText(_ provider: NSItemProvider) async -> ShareInboxEntry? {
        let identifier: String = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            ? UTType.url.identifier
            : UTType.plainText.identifier
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { loaded, _ in
                if let url = loaded as? URL {
                    continuation.resume(returning: ShareInboxEntry(kind: .text, text: url.absoluteString))
                } else if let text = loaded as? String {
                    continuation.resume(returning: ShareInboxEntry(kind: .text, text: text))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func readFile(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        kind: ShareInboxEntry.Kind
    ) async -> ShareInboxEntry? {
        // 先把 NSItemProvider 的可捕获属性值拷出来，避免在 @Sendable 回调里持有它。
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                guard let store = ShareInboxStore() else {
                    continuation.resume(returning: nil)
                    return
                }
                let resolvedName = suggestedName ?? url.lastPathComponent
                do {
                    let relative = try store.storeAttachment(sourceURL: url, suggestedName: resolvedName)
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
                    let entry = ShareInboxEntry(
                        kind: kind,
                        relativeFilePath: relative,
                        fileName: resolvedName,
                        fileSize: size
                    )
                    continuation.resume(returning: entry)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func finish(success: Bool, message: String) {
        Task { @MainActor in
            progressView.stopAnimating()
            statusLabel.text = message
            statusLabel.textColor = success ? .systemGreen : .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                if success {
                    self.extensionContext?.completeRequest(returningItems: nil)
                } else {
                    self.extensionContext?.cancelRequest(
                        withError: NSError(domain: "ThunderNoteShareExtension", code: -1, userInfo: nil)
                    )
                }
            }
        }
    }
}
