// Mirrors the episode links shared by schedule calendar cells and the mobile drawer.
import UIKit

final class ScheduleEpisodeRow: UIControl {
    var onSelect: (() -> Void)?

    init(episode: ScheduleAiringEpisode, showsEpisode: Bool) {
        super.init(frame: .zero)
        let title = UILabel()
        title.font = .nunito(ofSize: 12, weight: .medium)
        title.textColor = UIColor.HayaseTheme.foreground
        title.text = episode.titlePreferred ?? "Unknown"
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let number = UILabel()
        number.font = .nunito(ofSize: 12)
        number.textColor = UIColor.HayaseTheme.foreground
        number.text = "#" + String(episode.episode)
        number.isHidden = !showsEpisode
        number.setContentCompressionResistancePriority(.required, for: .horizontal)
        let time = UILabel()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        time.text = formatter.string(from: episode.airingAt)
        time.font = .nunito(ofSize: 12)
        time.textColor = UIColor.HayaseTheme.mutedForeground
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [title, number, time])
        if let entry = episode.entry, let status = entry.status {
            let colors: [String: UIColor] = [
                "CURRENT": UIColor(red: 61/255, green: 180/255, blue: 242/255, alpha: 1),
                "PLANNING": UIColor(red: 247/255, green: 154/255, blue: 99/255, alpha: 1),
                "COMPLETED": UIColor(red: 123/255, green: 213/255, blue: 85/255, alpha: 1),
                "PAUSED": UIColor(red: 250/255, green: 122/255, blue: 122/255, alpha: 1),
                "REPEATING": UIColor(red: 59/255, green: 174/255, blue: 234/255, alpha: 1),
            ]
            let watched = entry.progress >= episode.episode
            let mark = UIImageView()
            mark.contentMode = .scaleAspectFit
            mark.tintColor = colors[status] ?? UIColor.HayaseTheme.mutedForeground
            if watched { mark.image = UIImage.hayaseIcon("check") }
            else { mark.backgroundColor = mark.tintColor; mark.layer.cornerRadius = 4.4 }
            mark.isHidden = !watched && !showsEpisode
            mark.widthAnchor.constraint(equalToConstant: 8.8).isActive = true
            mark.heightAnchor.constraint(equalToConstant: 8.8).isActive = true
            stack.insertArrangedSubview(mark, at: 0)
        }
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        alpha = episode.airingAt < Date() ? 0.3 : 1
        accessibilityLabel = [title.text, number.text, time.text].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .link
        addTarget(self, action: #selector(selectEpisode), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func selectEpisode() { onSelect?() }
}
