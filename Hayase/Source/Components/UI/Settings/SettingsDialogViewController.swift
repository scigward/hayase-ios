// Mirrors: src/lib/components/ui/dialog/{dialog-content,dialog-overlay}.svelte
import UIKit

class SettingsDialogViewController: UIViewController {
    let content = UIStackView()
    var onClose: (() -> Void)?
    /// Only content with `!w-auto` (such as the torrent-library confirmation)
    /// opts into shrink-to-fit. Existing settings dialogs remain full-width.
    var preferredPanelWidth: CGFloat?
    let panel = UIView()
    private let backdrop = UIControl()
    private let stripedBackdrop = HayaseStripedBackdropView()
    private let heading: String
    private let maximumWidth: CGFloat
    private let contentInset: CGFloat
    private let heightFraction: CGFloat
    private var closing = false
    private var panelAnimator: UIViewPropertyAnimator?

    init(title: String, maximumWidth: CGFloat = 512, contentInset: CGFloat = 24, heightFraction: CGFloat = 0.95) {
        heading = title
        self.maximumWidth = maximumWidth
        self.contentInset = contentInset
        self.heightFraction = heightFraction
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Like the cover modal, let only the shared striped backdrop render
        // behind the panel (EntryEditor inherits this presentation too).
        view.backgroundColor = .clear
        backdrop.backgroundColor = .clear
        stripedBackdrop.isUserInteractionEnabled = false
        backdrop.addSubview(stripedBackdrop)
        backdrop.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(backdrop)
        panel.backgroundColor = UIColor.HayaseTheme.popover
        panel.layer.borderWidth = 1
        panel.clipsToBounds = true
        panel.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        panel.accessibilityViewIsModal = true
        view.addSubview(panel)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        if !heading.isEmpty {
            content.insertArrangedSubview(SettingsTypography.label(heading, size: 18, lineHeight: 18, weight: .bold), at: 0)
        }
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: contentInset),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: contentInset),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -contentInset),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -contentInset),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let closeButton = HayaseCloseButton()
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        stripedBackdrop.frame = backdrop.bounds
        let width = min(min(maximumWidth, view.bounds.width), preferredPanelWidth ?? maximumWidth)
        let viewport = view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
        content.arrangedSubviews.compactMap { $0 as? SettingsResponsiveView }
            .forEach { $0.updateLayout(viewportWidth: viewport) }
        let size = content.systemLayoutSizeFitting(CGSize(width: max(0, width - contentInset * 2), height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let visibleBottom = min(safe.maxY, view.keyboardLayoutGuide.layoutFrame.minY)
        let visibleHeight = max(0, visibleBottom - safe.minY)
        let height = min(size.height + contentInset * 2, visibleHeight * heightFraction)
        panel.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        panel.center = CGPoint(x: view.bounds.midX, y: safe.minY + visibleHeight / 2)
        panel.layer.cornerRadius = viewport >= 640 ? 8 : 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        panel.alpha = 0
        panel.transform = CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.95, y: 0.95)
        backdrop.alpha = 0
        UIView.animate(withDuration: 0.15) { self.backdrop.alpha = 1 }
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3, y: 1),
                                             controlPoint2: CGPoint(x: 2.0 / 3, y: 1))
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: timing)
        animator.addAnimations { self.panel.alpha = 1; self.panel.transform = .identity }
        panelAnimator = animator
        animator.startAnimation()
    }

    @objc func close() {
        guard !closing else { return }
        closing = true
        view.endEditing(true)
        panelAnimator?.stopAnimation(true)
        guard !UIAccessibility.isReduceMotionEnabled else {
            dismiss(animated: false, completion: onClose)
            return
        }
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveLinear) { self.backdrop.alpha = 0 }
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3, y: 0),
                                             controlPoint2: CGPoint(x: 2.0 / 3, y: 0))
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: timing)
        animator.addAnimations {
            self.panel.alpha = 0
            self.panel.transform = CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.95, y: 0.95)
        }
        animator.addCompletion { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: false, completion: self.onClose)
        }
        panelAnimator = animator
        animator.startAnimation()
    }
    override func accessibilityPerformEscape() -> Bool { close(); return true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(close))]
    }
}

// Non-blocking errors preserve the source toast interaction; no alert interrupts editing.
enum SettingsToast {
    static func show(_ message: String, in view: UIView) {
        let label = SettingsTypography.label(message, size: 13, lineHeight: 20)
        label.backgroundColor = UIColor.HayaseTheme.background
        label.layer.borderWidth = 1
        label.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        label.layer.cornerRadius = 8
        let container = UIView()
        container.backgroundColor = UIColor.HayaseTheme.background
        container.layer.cornerRadius = 8
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        label.layer.borderWidth = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 356),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        UIAccessibility.post(notification: .announcement, argument: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak container] in container?.removeFromSuperview() }
    }
}
