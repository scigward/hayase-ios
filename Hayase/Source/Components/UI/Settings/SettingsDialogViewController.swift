// Mirrors: src/lib/components/ui/dialog/{dialog-content,dialog-overlay}.svelte
import UIKit

class SettingsDialogViewController: UIViewController, UIGestureRecognizerDelegate, KeyboardEventListener {
    let content = UIStackView()
    var onClose: (() -> Void)?
    /// Only content with `!w-auto` (such as the torrent-library confirmation)
    /// opts into shrink-to-fit. Existing settings dialogs remain full-width.
    var preferredPanelWidth: CGFloat?
    /// `max-h-[80%]` and the like. A dialog without one is as tall as its content, whatever the window is.
    var limitsHeight = true
    /// `bg-popover`, or `bg-background` for the dialogs that ask for it
    var panelColor = UIColor.HayaseTheme.popover
    let panel = UIView()
    private let backdrop = UIControl()
    private let stripedBackdrop = HayaseStripedBackdropView()
    private let heading: String
    private let maximumWidth: CGFloat
    private let contentInset: CGFloat
    private let heightFraction: CGFloat
    /// The space between the edge of the panel and the content: its padding (`p-6`, or `p-0`) and the 1pt
    /// `border` of `Dialog.Content`, which is outside of the padding.
    private var inset: CGFloat { contentInset + 1 }
    private var closing = false
    private var panelAnimator: UIViewPropertyAnimator?
    private let scrollView = UIScrollView()
    /// The text input that has the focus, which is brought into view above the keyboard.
    private weak var activeInput: UIView?

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
        panel.backgroundColor = panelColor
        panel.layer.borderWidth = 1
        // The corners are clipped where the content reaches them (the scroll view, below), so the panel
        // itself can have its own `shadow-lg`: `0 10px 15px -3px rgb(0 0 0 / 0.1)`.
        panel.clipsToBounds = false
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.1
        panel.layer.shadowOffset = CGSize(width: 0, height: 10)
        panel.layer.shadowRadius = 7.5
        panel.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        panel.accessibilityViewIsModal = true
        view.addSubview(panel)
        let scroll = scrollView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.clipsToBounds = true
        panel.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        if !heading.isEmpty {
            content.insertArrangedSubview(SettingsTypography.label(heading, size: 18, lineHeight: 18, weight: .bold), at: 0)
        }
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: inset),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: inset),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -inset),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -inset),
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
            // `absolute right-4 top-4` is measured from the padding edge, inside the 1pt border
            closeButton.topAnchor.constraint(equalTo: panel.topAnchor, constant: 17),
            closeButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -17),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        // what a page does with an input: a click anywhere else takes the focus off it, and the input
        // that has the focus is scrolled into view
        let blur = UITapGestureRecognizer(target: self, action: #selector(blurInput))
        blur.cancelsTouchesInView = false
        blur.delegate = self
        panel.addGestureRecognizer(blur)
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(editingBegan(_:)),
                                  name: UITextField.textDidBeginEditingNotification, object: nil)
        notifications.addObserver(self, selector: #selector(editingBegan(_:)),
                                  name: UITextView.textDidBeginEditingNotification, object: nil)
        notifications.addObserver(self, selector: #selector(keyboardShown),
                                  name: UIResponder.keyboardDidShowNotification, object: nil)
    }

    @objc private func blurInput() {
        view.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // a touch on an input is the one that gives it the focus, and one on a web view (the trailer) is its own
        var current = touch.view
        while let touched = current, touched !== panel {
            if touched is UITextField || touched is UITextView { return false }
            if touched is UIScrollView && touched !== scrollView { return false }
            current = touched.superview
        }
        return true
    }

    @objc private func editingBegan(_ notification: Notification) {
        guard let input = notification.object as? UIView, input.isDescendant(of: scrollView) else { return }
        activeInput = input
        revealActiveInput()
    }

    @objc private func keyboardShown() {
        revealActiveInput()
    }

    /// The keyboard makes the panel smaller, so the input is scrolled into view once that is laid out.
    private func revealActiveInput() {
        guard let input = activeInput, input.isFirstResponder else { return }
        DispatchQueue.main.async { [weak self, weak input] in
            guard let self, let input, input.isFirstResponder, input.isDescendant(of: self.scrollView) else { return }
            self.view.layoutIfNeeded()
            let rect = self.scrollView.convert(input.bounds, from: input).insetBy(dx: 0, dy: -12)
            self.scrollView.scrollRectToVisible(rect, animated: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        stripedBackdrop.frame = backdrop.bounds
        let width = min(min(maximumWidth, view.bounds.width), preferredPanelWidth ?? maximumWidth)
        let viewport = view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
        content.arrangedSubviews.compactMap { $0 as? SettingsResponsiveView }
            .forEach { $0.updateLayout(viewportWidth: viewport) }
        let size = content.systemLayoutSizeFitting(CGSize(width: max(0, width - inset * 2), height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        // `Dialog.Portal` is `fixed inset-0` and the dialog is `top-[50%]` with `max-h-[80%]` of it: the middle
        // of the window and a share of its height, whatever the safe areas are. Only while the keyboard is up
        // is the window what is above it, which is what the window of a phone becomes with a keyboard.
        let safe = view.safeAreaLayoutGuide.layoutFrame
        // the keyboard guide ends at the safe area while there is no keyboard
        let keyboardTop = view.keyboardLayoutGuide.layoutFrame.minY
        let windowBottom = keyboardTop < safe.maxY - 1 ? keyboardTop : view.bounds.maxY
        let limit = limitsHeight ? windowBottom * heightFraction : CGFloat.greatestFiniteMagnitude
        let height = min(size.height + inset * 2, limit)
        panel.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        panel.center = CGPoint(x: view.bounds.midX, y: windowBottom / 2)
        let radius: CGFloat = viewport >= 640 ? 8 : 0   // sm:rounded-lg
        panel.layer.cornerRadius = radius
        // content that reaches the corners (`p-0`) is clipped to the inside of the border
        scrollView.layer.cornerRadius = contentInset == 0 ? max(0, radius - 1) : 0
        // `-3px` of spread
        panel.layer.shadowPath = UIBezierPath(roundedRect: panel.bounds.insetBy(dx: 3, dy: 3),
                                              cornerRadius: max(0, radius - 3)).cgPath
    }

    /// `flyAndScale` of `Dialog.Content` in and out: from 5pt below and 95%, over 200ms with `cubicOut`;
    /// out is the same curve on the way back, since a transition out plays its easing forwards too.
    private static let panelTiming = UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3, y: 1),
                                                             controlPoint2: CGPoint(x: 2.0 / 3, y: 1))
    private static let panelHidden = CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.95, y: 0.95)

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // from the first frame, not one frame after it
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        panel.alpha = 0
        panel.transform = Self.panelHidden
        backdrop.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        // `Dialog.Overlay`: `transition:fade={{ duration: 150 }}`, which is linear
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveLinear) { self.backdrop.alpha = 1 }
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: Self.panelTiming)
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
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: Self.panelTiming)
        animator.addAnimations {
            self.panel.alpha = 0
            self.panel.transform = Self.panelHidden
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
        [.keydown(KeyboardEvent.Key.escape)]
    }

    /// `useEscapeKeydown`: the dialog that is the closest to the key closes, and the key is its alone
    func keyDown(_ event: KeyboardEvent) {
        guard event.key == KeyboardEvent.Key.escape else { return }
        close()
        event.preventDefault()
        event.stopPropagation()
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
