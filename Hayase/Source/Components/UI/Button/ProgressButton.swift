//
//  ProgressButton.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/progress-button.svelte: a button that fills while it counts down to its
//  action, which is taken when the fill ends or when the button is pressed. It is a `Button` (`variant='default'`,
//  `size='default'`, `font-bold`, `px-7`), so it has the colours of `select:`, the press scale of app.css and the
//  D-pad's focus like every other button; `overflow-hidden` clips the fill, not the shadow.
//

import UIKit

final class InterfaceProgressButton: SelectButton {
    /// `overflow-hidden`: what clips the fill
    private let clip = UIView()
    /// `absolute inset-0 bg-background/20 pointer-events-none translate-x-full`
    private let progressView = UIView()
    private var pendingCompletion = false
    var isAnimatingProgress: Bool { pendingCompletion }
    var onTrigger: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyPrimaryVariant()
        titleLabel?.font = .nunito(ofSize: 14, weight: .bold)
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 28, bottom: 0, right: 28)   // px-7

        clip.clipsToBounds = true
        clip.layer.cornerRadius = layer.cornerRadius
        clip.isUserInteractionEnabled = false
        clip.translatesAutoresizingMaskIntoConstraints = false
        progressView.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        progressView.isUserInteractionEnabled = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(progressView)
        // after the text, as in the page: the fill is over it
        addSubview(clip)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            clip.topAnchor.constraint(equalTo: topAnchor),
            clip.leadingAnchor.constraint(equalTo: leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor),
            clip.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressView.topAnchor.constraint(equalTo: clip.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
        ])
        addTarget(self, action: #selector(triggerNow), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        bringSubviewToFront(clip)
        if !pendingCompletion {
            progressView.transform = CGAffineTransform(translationX: bounds.width, y: 0)
        }
    }

    func setTitle(_ title: String) {
        setTitle(title, for: .normal)
        invalidateIntrinsicContentSize()
    }

    func startProgress(duration: TimeInterval) {
        guard !pendingCompletion else { return }
        pendingCompletion = true
        layoutIfNeeded()
        progressView.layer.removeAllAnimations()
        progressView.transform = .identity
        UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear]) {
            self.progressView.transform = CGAffineTransform(translationX: self.bounds.width, y: 0)
        } completion: { [weak self] finished in
            guard let self, finished, self.pendingCompletion else { return }
            self.pendingCompletion = false
            self.progressView.transform = CGAffineTransform(translationX: self.bounds.width, y: 0)
            self.onTrigger?()
        }
    }

    func stopProgress() {
        pendingCompletion = false
        progressView.layer.removeAllAnimations()
        progressView.transform = CGAffineTransform(translationX: bounds.width, y: 0)
    }

    @objc private func triggerNow() {
        stopProgress()
        onTrigger?()
    }
}
