import UIKit

/// 占位的 Share Extension。完整实现（写入 App Group ShareInbox + 主 App 消费）
/// 在 D2-I5-07 / D2-I5-08 阶段补齐；当前仅给系统一个最小可交互入口。
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "闪记分享开发中（I-5 阶段启用）"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.cancelRequest(
                withError: NSError(domain: "ThunderNoteShareExtension", code: -1, userInfo: nil)
            )
        }
    }
}
