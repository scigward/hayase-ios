//
//  Videoframe.swift
//  Hayase
//
//  Mirrors interface cards/videoframe.svelte for trace preview architecture.
//

import AVFoundation
import UIKit

final class Videoframe: UIView {
    var onHide: ((Bool) -> Void)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentURLString: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func configure(src: String?) {
        guard let src, !src.isEmpty, let url = URL(string: src) else {
            reset()
            return
        }
        guard currentURLString != src else { return }
        currentURLString = src

        let player = AVPlayer(url: url)
        player.isMuted = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        self.player = player
        self.playerLayer = layer
        player.play()
        onHide?(false)
    }

    func reset() {
        currentURLString = nil
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        onHide?(true)
    }
}
