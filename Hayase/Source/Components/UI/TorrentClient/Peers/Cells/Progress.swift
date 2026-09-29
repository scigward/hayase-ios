//
//  Progress.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class PeerProgressCellContent: UIView {
    private let trackView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.HayaseTheme.secondary
        view.layer.cornerRadius = 3
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let fillView: UIView = {
        let view = UIView()
        view.backgroundColor = TorrentClientStyle.primary
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.font = .nunito(ofSize: 12)
        label.textColor = TorrentClientStyle.mutedForeground
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var progress: Double = 0

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

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFillTransform()
    }

    private func setup() {
        addSubview(trackView)
        trackView.addSubview(fillView)
        addSubview(label)

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            trackView.heightAnchor.constraint(equalToConstant: 6),

            fillView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            fillView.trailingAnchor.constraint(equalTo: trackView.trailingAnchor),
            fillView.topAnchor.constraint(equalTo: trackView.topAnchor),
            fillView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor),

            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: trackView.bottomAnchor, constant: 4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    func configure(progress: Double) {
        self.progress = max(0, min(progress, 1))
        label.text = String(format: "%.1f%%", self.progress * 100)
        updateFillTransform()
    }

    private func updateFillTransform() {
        let offset = CGFloat(progress - 1) * trackView.bounds.width
        fillView.transform = CGAffineTransform(translationX: offset, y: 0)
    }
}
