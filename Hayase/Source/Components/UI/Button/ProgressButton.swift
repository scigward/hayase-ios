//
//  ProgressButton.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/button/progress-button.svelte: a button that fills while it counts down to its
//  action, which is taken when the fill ends or when the button is pressed.
//

import UIKit
import AVKit
import CoreMedia
import UniformTypeIdentifiers

final class InterfaceProgressButton: UIControl {
    private let label = UILabel()
    private let progressView = UIView()
    private var pendingCompletion = false
    var isAnimatingProgress: Bool { pendingCompletion }
    var onTrigger: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.HayaseTheme.primary
        layer.cornerRadius = 6
        clipsToBounds = true

        label.font = .nunito(ofSize: 14, weight: .bold)
        label.textColor = UIColor.HayaseTheme.primaryForeground
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        progressView.backgroundColor = UIColor.HayaseTheme.background.withAlphaComponent(0.2)
        progressView.isUserInteractionEnabled = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.topAnchor.constraint(equalTo: topAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        sendSubviewToBack(progressView)
        addTarget(self, action: #selector(triggerNow), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !pendingCompletion {
            progressView.transform = CGAffineTransform(translationX: bounds.width, y: 0)
        }
    }

    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(width: labelSize.width + 56, height: 36)
    }

    func setTitle(_ title: String) {
        label.text = title
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

