import UIKit

/// Native counterpart of the interface's 15-second torrent error toasts.
/// Keep errors outside the metadata/player surface and above route presentations.
@MainActor
enum TorrentErrorToast {
    private static weak var stack: UIStackView?
    private static var recentlyShown: [String: Date] = [:]

    static func show(_ message: String, title: String = "Torrent Process Error!") {
        guard let window = (UIApplication.shared.delegate as? AppDelegate)?.window else { return }
        let now = Date()
        recentlyShown = recentlyShown.filter { now.timeIntervalSince($0.value) < 15 }
        // The same failure may arrive through both an event and an RPC response.
        guard recentlyShown[message] == nil else { return }
        recentlyShown[message] = now
        let host: UIStackView
        if let existing = stack, existing.superview === window {
            host = existing
        } else {
            host = UIStackView()
            host.axis = .vertical
            host.spacing = 8
            host.translatesAutoresizingMaskIntoConstraints = false
            window.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 24),
                host.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                host.leadingAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                host.widthAnchor.constraint(lessThanOrEqualToConstant: 356),
            ])
            let preferredWidth = host.widthAnchor.constraint(equalToConstant: 356)
            preferredWidth.priority = .defaultHigh
            preferredWidth.isActive = true
            stack = host
        }
        window.bringSubviewToFront(host)
        while host.arrangedSubviews.count >= 3 { host.arrangedSubviews.last?.removeFromSuperview() }
        let heading = SettingsTypography.label(title, size: 13, lineHeight: 20, weight: .semibold)
        let description = SettingsTypography.label(message, size: 13, lineHeight: 20,
            color: UIColor.HayaseTheme.mutedForeground)
        let text = UIStackView(arrangedSubviews: [heading, description])
        text.axis = .vertical
        text.spacing = 4
        let icon = UIImageView(image: UIImage.hayaseIcon("circle-alert", pointSize: 16))
        icon.tintColor = UIColor.HayaseTheme.foreground
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let close = HayaseCloseButton()
        close.widthAnchor.constraint(equalToConstant: 16).isActive = true
        close.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let row = UIStackView(arrangedSubviews: [icon, text, close])
        row.alignment = .top
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        row.backgroundColor = UIColor.HayaseTheme.background
        row.layer.cornerRadius = 8
        row.layer.borderWidth = 1
        row.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        row.layer.shadowColor = UIColor.black.cgColor
        row.layer.shadowOpacity = 0.1
        row.layer.shadowOffset = CGSize(width: 0, height: 10)
        row.layer.shadowRadius = 7.5
        host.insertArrangedSubview(row, at: 0)
        close.addAction(UIAction { [weak row] _ in row?.removeFromSuperview() }, for: .touchUpInside)
        UIAccessibility.post(notification: .announcement, argument: title + "\n" + message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak row] in row?.removeFromSuperview() }
    }
}
