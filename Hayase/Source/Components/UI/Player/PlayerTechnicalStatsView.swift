// Mirrors player/statsfornerds.svelte. Metrics come from MPV, not invented browser counters.
import UIKit

final class PlayerTechnicalStatsView: UIView {
    var onClose: (() -> Void)?
    private var values: [String: UILabel] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 25)
        layer.shadowRadius = 25
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 12
        card.layer.borderColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.1).cgColor
        card.layer.borderWidth = 1
        card.clipsToBounds = true
        addSubview(card)
        // Public UIKit blur keeps live video visible behind the panel. CSS's
        // 24px backdrop-blur-xl has no public radius equivalent on iOS.
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        blur.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(blur)
        let tint = UIView()
        tint.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.7)
        tint.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(tint)
        let content = UIStackView()
        content.axis = .vertical
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        let header = UIView()
        let title = label("Stats for Nerds", size: 14, alpha: 0.9, weight: .semibold)
        let close = SelectButton(frame: .zero)
        close.applyGhostVariant()
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setImage(UIImage.hayaseIcon("x", pointSize: 16), for: .normal)
        close.accessibilityLabel = "Close Stats for Nerds"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        header.addSubview(title)
        header.addSubview(close)
        content.addArrangedSubview(header)
        content.addArrangedSubview(separator(alpha: 0.1))
        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 12
        body.isLayoutMarginsRelativeArrangement = true
        body.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.addArrangedSubview(body)
        let groups: [(String, [String])] = [
            ("Video", ["Resolution", "Viewport"]),
            ("Performance", ["FPS", "Presented Frames", "Frame Time", "Dropped Frames"]),
            ("Playback", ["Position", "Speed", "Volume", "Subtitle Delay", "Ready State"]),
            ("Tracks", ["Audio", "Video"]), ("Buffer", ["Health"]),
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { body.addArrangedSubview(separator(alpha: 0.05)) }
            let section = UIStackView()
            section.axis = .vertical
            section.spacing = 6
            section.addArrangedSubview(label(group.0.uppercased(), size: 10, alpha: 0.5, weight: .medium))
            let rows = UIStackView()
            rows.axis = .vertical
            rows.spacing = 4
            for name in group.1 {
                let value = label("-", size: 12, alpha: 1)
                value.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                value.textAlignment = .right
                value.setContentCompressionResistancePriority(.required, for: .horizontal)
                let row = UIStackView(arrangedSubviews: [label(name, size: 12, alpha: 0.6), value])
                row.spacing = 4
                row.alignment = .center
                rows.addArrangedSubview(row)
                values[name] = value
            }
            section.addArrangedSubview(rows)
            body.addArrangedSubview(section)
        }
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor), card.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: card.leadingAnchor), blur.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            blur.topAnchor.constraint(equalTo: card.topAnchor), blur.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: card.leadingAnchor), tint.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            tint.topAnchor.constraint(equalTo: card.topAnchor), tint.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor), content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor), content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            close.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            close.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
            close.widthAnchor.constraint(equalToConstant: 28), close.heightAnchor.constraint(equalToConstant: 28),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ metrics: [String: String]) { for (name, value) in metrics { values[name]?.text = value } }
    @objc private func closeTapped() { onClose?() }
    private func label(_ text: String, size: CGFloat, alpha: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .nunito(ofSize: size, weight: weight)
        label.textColor = UIColor.HayaseTheme.foreground.withAlphaComponent(alpha)
        label.text = text
        return label
    }
    private func separator(alpha: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.foreground.withAlphaComponent(alpha)
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }
}
