import UIKit
import AVFoundation

/// A UIView backed by AVSampleBufferDisplayLayer. MPVWrapper renders directly into this layer.
final class MPVSurfaceView: UIView {

    private let displayLayer = AVSampleBufferDisplayLayer()
    private(set) var mpv: MPVWrapper!

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        layer.addSublayer(displayLayer)
        mpv = MPVWrapper(displayLayer: displayLayer)
        mpv.start()
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
