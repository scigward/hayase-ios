//
//  Progress.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerProgressCellContent: UIView {
    private let trackView = TorrentClientProgressBar()

    private let label: UILabel = {
        let label = TorrentClientLabel()
        label.lineHeight = 16
        label.font = .nunito(ofSize: 12)
        label.textColor = TorrentClientStyle.mutedForeground
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var progress: Double = 0
    private var hasConfigured = false

    // The horizontal row centers this view; UIView has no intrinsic height.
    // Match mt-1.5 + h-1.5 + mt-1 + text-xs (16px line height).
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 32)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)
        addSubview(label)

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            trackView.heightAnchor.constraint(equalToConstant: 6),

            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: trackView.bottomAnchor, constant: 4),
            label.heightAnchor.constraint(equalToConstant: 16),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    func configure(progress: Double, animated: Bool = true) {
        let previousProgress = self.progress
        self.progress = max(0, min(progress, 1))
        label.text = String(format: "%.1f%%", self.progress * 100)
        if previousProgress != self.progress || !hasConfigured {
            trackView.animatesUpdates = animated && hasConfigured
            trackView.progress = Float(self.progress)
        }
        hasConfigured = true
    }
}
