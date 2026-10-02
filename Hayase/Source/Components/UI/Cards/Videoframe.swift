//
//  Videoframe.swift
//  Hayase
//
//  Mirrors interface cards/videoframe.svelte: the looping clip a trace result's preview card plays.
//

import AVFoundation
import UIKit

final class Videoframe: UIView {
    var onHide: ((Bool) -> Void)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentURLString: String?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var isMuted = true

    /// `<div class='absolute z-10 top-0 right-0 p-3'>` around a 16px icon.
    private let muteButton: UIButton = {
        let button = UIButton(type: .system)
        button.tintColor = UIColor.HayaseTheme.foreground
        button.alpha = 0
        button.isHidden = true
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true
        addSubview(muteButton)
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        updateMuteIcon()
    }

    /// Only the mute button takes touches; everything else of the frame is a picture.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === muteButton ? hit : nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // `h-[calc(100%+200px)]` and centred: the clip is as wide as the frame and shown whole,
        // so a short frame crops it above and below.
        playerLayer?.frame = CGRect(x: 0, y: -100, width: bounds.width, height: bounds.height + 200)
        muteButton.frame = CGRect(x: bounds.width - 40, y: 0, width: 40, height: 40)
    }

    func configure(src: String?) {
        guard let src, !src.isEmpty, let url = URL(string: src) else {
            reset()
            return
        }
        guard currentURLString != src else { return }
        reset()
        currentURLString = src

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.volume = 0.2   // volume={0.2}
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.opacity = 0
        self.layer.insertSublayer(layer, below: muteButton.layer)
        self.player = player
        self.playerLayer = layer
        setNeedsLayout()

        // `loop`
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        // `on:loadeddata`: the clip and its mute button fade in once the first frame is there
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async { self?.clipLoaded() }
        }
        player.play()
    }

    private func clipLoaded() {
        guard playerLayer != nil else { return }
        muteButton.isHidden = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)   // `transition: opacity 0.3s`
        playerLayer?.opacity = 1
        CATransaction.commit()
        UIView.animate(withDuration: 0.3) { self.muteButton.alpha = 1 }
        onHide?(false)
    }

    func reset() {
        let hadClip = currentURLString != nil
        currentURLString = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        muteButton.layer.removeAllAnimations()
        muteButton.alpha = 0
        muteButton.isHidden = true
        if hadClip { onHide?(true) }
    }

    @objc private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        updateMuteIcon()
    }

    private func updateMuteIcon() {
        muteButton.setImage(UIImage.hayaseFilledIcon(isMuted ? "volume-x" : "volume-2", pointSize: 16), for: .normal)
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}
