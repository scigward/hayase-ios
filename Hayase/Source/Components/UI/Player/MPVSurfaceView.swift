import UIKit
import AVFoundation

// MARK: - Legacy Models for UI
// Included here so UI doesn't break, bridging the gap from Streamyfin's dictionary returns.

public struct PlayerPreset {
    public var commands: [[String]] = []
    public init(commands: [[String]] = []) { self.commands = commands }
}

struct MPVTrack {
    let id: Int
    let type: String
    let title: String?
    let lang: String?
    let isSelected: Bool
    /// `forced` and `default` of the track, which the choice of the subtitle track looks at
    var isForced = false
    var isDefault = false

    var displayName: String {
        if let t = title, !t.isEmpty { return t }
        if let l = lang,  !l.isEmpty { return l }
        return "\(type.capitalized) \(id)"
    }
}

struct MPVChapter {
    let index: Int
    let title: String
    let time: Double
}

/// A UIView backed by AVSampleBufferDisplayLayer. MPVLayerRenderer renders directly into this layer.
final class MPVSurfaceView: UIView {

    let displayLayer = AVSampleBufferDisplayLayer()
    private(set) var mpv: MPVWrapper!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        layer.addSublayer(displayLayer)
        mpv = MPVWrapper(displayLayer: displayLayer)
        try? mpv.start()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: - Stop

    func stop() { mpv.stop() }

    deinit { mpv?.stop() }
}