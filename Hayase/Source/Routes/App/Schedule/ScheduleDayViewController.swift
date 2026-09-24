// Mirrors schedule's Drawer.Content, Header and Footer, without a native action sheet.
import UIKit

final class ScheduleDayViewController: UIViewController {
    private let episodes: [ScheduleAiringEpisode]
    private let select: (Int) -> Void
    private let backdrop = HayaseStripedBackdropView(dimColor: UIColor.black.withAlphaComponent(0.55))
    private let panel = UIView()
    private let border = UIView()
    private let scroll = UIScrollView()
    private let rows = UIStackView()
    private let closeButton = UIButton(type: .custom)

    init(episodes: [ScheduleAiringEpisode], select: @escaping (Int) -> Void) {
        self.episodes = episodes
        self.select = select
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(backdrop)
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        panel.backgroundColor = UIColor.HayaseTheme.background
        panel.accessibilityViewIsModal = true
        view.addSubview(panel)
        border.backgroundColor = UIColor.HayaseTheme.border.withAlphaComponent(0.6)
        panel.addSubview(border)
        panel.addSubview(scroll)
        rows.axis = .vertical
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rows)
        for episode in episodes {
            let row = ScheduleEpisodeRow(episode: episode, showsEpisode: true)
            row.onSelect = { [weak self] in
                guard let self else { return }
                self.dismiss(animated: false) { self.select(episode.mediaID) }
            }
            rows.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24),
        ])
        closeButton.setImage(UIImage.hayaseIcon("x"), for: .normal)
        closeButton.tintColor = UIColor.HayaseTheme.foreground.withAlphaComponent(0.7)
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        panel.addSubview(closeButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        let height = min(max(0, view.bounds.height - 96), CGFloat(episodes.count) * 22 + 68 + view.safeAreaInsets.bottom)
        panel.frame = CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height)
        border.frame = CGRect(x: 0, y: 0, width: panel.bounds.width, height: 4)
        closeButton.frame = CGRect(x: panel.bounds.width - 32, y: 16, width: 16, height: 16)
        scroll.frame = CGRect(x: 16, y: 48, width: max(0, panel.bounds.width - 32),
                              height: max(0, height - 64 - view.safeAreaInsets.bottom))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = panel.bounds.height
        slide.toValue = 0
        slide.duration = 0.3
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.layer.add(slide, forKey: "drawer-open")
    }
    @objc private func close() { dismiss(animated: false) }
    override func accessibilityPerformEscape() -> Bool { close(); return true }
}
