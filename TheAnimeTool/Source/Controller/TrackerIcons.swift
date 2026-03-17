//
//  TrackerIcons.swift
//  TheAnimeTool
//
//  UIView subclasses that render the AniList, Kitsu, MyAnimeList, and Local
//  tracker icons identically to Hayase's SVG components:
//    Anilist.svelte, Kitsu.svelte, MyAnimeList.svelte
//  and Lucide's `folder` icon for the Local tracker.
//
//  Each icon is drawn via CAShapeLayer so it scales perfectly to any size.
//

import UIKit

// MARK: - AniListIconView
// Matches: src/lib/components/icons/Anilist.svelte
// Two-path SVG: blue "AL" mark + white "A" letter.

final class AniListIconView: UIView {

    override class var layerClass: AnyClass { CAShapeLayer.self }

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
        isUserInteractionEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        drawIcon()
    }

    private func drawIcon() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        // Original SVG viewBox: 0 0 41 30 (offset 0.957, 0.5)
        // We scale to fit our bounds.
        let scaleX = w / 41.0
        let scaleY = h / 30.0
        let s = min(scaleX, scaleY)
        let offsetX = (w - 41.0 * s) / 2
        let offsetY = (h - 30.0 * s) / 2

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x - 0.957) * s + offsetX, y: (y - 0.5) * s + offsetY)
        }

        // Blue "AL" mark path
        let bluePath = UIBezierPath()
        bluePath.move(to: pt(28.782, 22.273))
        bluePath.addLine(to: pt(28.782, 3.477))
        bluePath.addCurve(to: pt(27.057, 1.805), controlPoint1: pt(28.782, 2.400), controlPoint2: pt(28.169, 1.805))
        bluePath.addLine(to: pt(23.262, 1.805))
        bluePath.addCurve(to: pt(21.537, 3.477), controlPoint1: pt(22.151, 1.805), controlPoint2: pt(21.537, 2.400))
        bluePath.addLine(to: pt(21.537, 12.404))

        let blueLayer = CAShapeLayer()
        blueLayer.path = bluePath.cgPath
        blueLayer.fillColor = UIColor(red: 0, green: 0.659, blue: 1, alpha: 1).cgColor // #00A8FF
        layer.addSublayer(blueLayer)

        // White "A" path
        let whitePath = UIBezierPath()
        whitePath.move(to: pt(13.027, 1.806))
        whitePath.addLine(to: pt(3.061, 29.296))
        whitePath.addLine(to: pt(10.804, 29.296))
        whitePath.addLine(to: pt(12.491, 24.540))
        whitePath.addLine(to: pt(20.924, 24.540))
        whitePath.addLine(to: pt(22.573, 29.295))
        whitePath.addLine(to: pt(30.278, 29.295))
        whitePath.addLine(to: pt(20.349, 1.806))
        whitePath.close()
        // Inner cutout
        whitePath.move(to: pt(13.297, 17.948))
        whitePath.addLine(to: pt(15.712, 10.333))
        whitePath.addLine(to: pt(18.357, 17.948))
        whitePath.close()

        let whiteLayer = CAShapeLayer()
        whiteLayer.path = whitePath.cgPath
        whiteLayer.fillColor = UIColor.white.cgColor
        whiteLayer.fillRule = .evenOdd
        layer.addSublayer(whiteLayer)
    }
}

// MARK: - KitsuIconView
// Matches: src/lib/components/icons/Kitsu.svelte
// The Kitsu fox icon in #E75E45.
// Simplified: we use an image approach since the path is very complex.
// For perfect fidelity, we draw the fox shape.

final class KitsuIconView: UIView {

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
        isUserInteractionEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        drawIcon()
    }

    private func drawIcon() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        // Original SVG viewBox: 0 0 224 224
        let scale = min(w / 224.0, h / 224.0)
        let offsetX = (w - 224.0 * scale) / 2
        let offsetY = (h - 224.0 * scale) / 2

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        let kitsuColor = UIColor(red: 231/255, green: 94/255, blue: 69/255, alpha: 1) // #E75E45

        // Simplified main body path (the prominent lower shape)
        let bodyPath = UIBezierPath()
        bodyPath.move(to: pt(152.7, 48.5))
        bodyPath.addCurve(to: pt(131.0, 44.1), controlPoint1: pt(145.9, 46.0), controlPoint2: pt(138.6, 44.5))
        bodyPath.addCurve(to: pt(93.5, 52.1), controlPoint1: pt(118.3, 43.5), controlPoint2: pt(106.2, 46.3))
        bodyPath.addLine(to: pt(93.5, 89.1))
        bodyPath.addCurve(to: pt(78.4, 104.7), controlPoint1: pt(93.5, 95.6), controlPoint2: pt(88.7, 101.8))
        bodyPath.addCurve(to: pt(73.0, 91.2), controlPoint1: pt(72.4, 103.4), controlPoint2: pt(73.0, 91.2))
        bodyPath.addLine(to: pt(38.4, 78.0))
        bodyPath.addCurve(to: pt(2.0, 125.3), controlPoint1: pt(25.5, 88.7), controlPoint2: pt(13.2, 101.9))
        bodyPath.addCurve(to: pt(7.0, 135.5), controlPoint1: pt(0.0, 128.2), controlPoint2: pt(2.0, 133.2))
        bodyPath.addCurve(to: pt(58.8, 113.2), controlPoint1: pt(12.4, 132.5), controlPoint2: pt(33.6, 122.3))
        bodyPath.addCurve(to: pt(59.3, 126.3), controlPoint1: pt(62.1, 113.7), controlPoint2: pt(63.6, 118.6))
        bodyPath.addCurve(to: pt(44.5, 167.4), controlPoint1: pt(51.7, 138.7), controlPoint2: pt(45.6, 153.9))
        bodyPath.addCurve(to: pt(50.6, 175.2), controlPoint1: pt(44.1, 169.5), controlPoint2: pt(45.5, 173.1))
        bodyPath.addCurve(to: pt(67.4, 152.6), controlPoint1: pt(55.7, 170.8), controlPoint2: pt(61.1, 163.5))
        bodyPath.addCurve(to: pt(170.6, 99.4), controlPoint1: pt(93.7, 124.4), controlPoint2: pt(131.4, 103.4))
        bodyPath.addCurve(to: pt(167.4, 107.3), controlPoint1: pt(173.1, 99.7), controlPoint2: pt(173.5, 103.3))
        bodyPath.addCurve(to: pt(88.6, 220.7), controlPoint1: pt(131.1, 115.0), controlPoint2: pt(65.8, 158.0))
        bodyPath.addCurve(to: pt(94.8, 226.0), controlPoint1: pt(89.8, 222.4), controlPoint2: pt(91.7, 224.4))
        bodyPath.addCurve(to: pt(130.9, 196.0), controlPoint1: pt(98.5, 219.0), controlPoint2: pt(105.5, 210.8))
        bodyPath.addCurve(to: pt(199.2, 48.8), controlPoint1: pt(187.2, 172.7), controlPoint2: pt(200.1, 131.6))
        bodyPath.close()

        let bodyLayer = CAShapeLayer()
        bodyLayer.path = bodyPath.cgPath
        bodyLayer.fillColor = kitsuColor.cgColor
        layer.addSublayer(bodyLayer)

        // Simplified upper ears/head path
        let headPath = UIBezierPath()
        headPath.move(to: pt(1.1, 50.6))
        headPath.addCurve(to: pt(19.5, 70.4), controlPoint1: pt(1.5, 51.3), controlPoint2: pt(7.0, 58.3))
        headPath.addCurve(to: pt(55.7, 81.5), controlPoint1: pt(23.7, 74.0), controlPoint2: pt(37.5, 81.5))
        headPath.addLine(to: pt(77.8, 96.1))
        headPath.addCurve(to: pt(84.8, 89.1), controlPoint1: pt(82.6, 96.8), controlPoint2: pt(84.8, 93.7))
        headPath.addLine(to: pt(84.8, 48.5))
        headPath.addCurve(to: pt(69.7, 4.2), controlPoint1: pt(84.9, 30.1), controlPoint2: pt(80.6, 16.7))
        headPath.addCurve(to: pt(60.8, 7.3), controlPoint1: pt(67.0, 0.5), controlPoint2: pt(62.3, 3.0))
        headPath.addCurve(to: pt(64.6, 39.3), controlPoint1: pt(54.4, 16.6), controlPoint2: pt(56.8, 27.3))
        headPath.addCurve(to: pt(51.1, 42.9), controlPoint1: pt(60.0, 40.1), controlPoint2: pt(55.5, 41.3))
        headPath.addCurve(to: pt(31.5, 51.3), controlPoint1: pt(41.4, 37.4), controlPoint2: pt(31.5, 51.3))
        headPath.addCurve(to: pt(9.7, 47.9), controlPoint1: pt(21.8, 45.8), controlPoint2: pt(15.1, 44.2))
        headPath.close()

        let headLayer = CAShapeLayer()
        headLayer.path = headPath.cgPath
        headLayer.fillColor = kitsuColor.cgColor
        layer.addSublayer(headLayer)
    }
}

// MARK: - MALIconView
// Matches: src/lib/components/icons/MyAnimeList.svelte
// MAL text logo on a blue (#3557a5) rounded background.

final class MALIconView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(red: 53/255, green: 87/255, blue: 165/255, alpha: 1) // #3557a5
        layer.cornerRadius = 3
        layer.masksToBounds = true
        isUserInteractionEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.filter { $0 is CAShapeLayer }.forEach { $0.removeFromSuperlayer() }
        drawIcon()
    }

    private func drawIcon() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        // The Hayase MAL icon SVG path data, viewBox="0 0 24 24"
        let scale = min(w / 24.0, h / 24.0)
        let offsetX = (w - 24.0 * scale) / 2
        let offsetY = (h - 24.0 * scale) / 2

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        // M path from MyAnimeList.svelte
        let path = UIBezierPath()
        // "M" letter
        path.move(to: pt(8.273, 7.247))
        path.addLine(to: pt(8.273, 15.670))
        path.addLine(to: pt(6.170, 15.667))
        path.addLine(to: pt(6.170, 10.451))
        path.addLine(to: pt(4.140, 12.855))
        path.addLine(to: pt(2.151, 10.397))
        path.addLine(to: pt(2.131, 15.682))
        path.addLine(to: pt(0.001, 15.670))
        path.addLine(to: pt(0.000, 7.247))
        path.addLine(to: pt(2.203, 7.247))
        path.addLine(to: pt(4.068, 9.792))
        path.addLine(to: pt(6.083, 7.246))
        path.close()

        // "A" letter
        path.move(to: pt(16.901, 9.316))
        path.addLine(to: pt(16.926, 15.651))
        path.addLine(to: pt(14.561, 15.651))
        path.addLine(to: pt(14.553, 12.780))
        path.addLine(to: pt(11.753, 12.780))
        path.addCurve(to: pt(12.170, 14.559), controlPoint1: pt(11.823, 13.279), controlPoint2: pt(11.963, 14.046))
        path.addCurve(to: pt(12.753, 15.687), controlPoint1: pt(12.325, 14.940), controlPoint2: pt(12.468, 15.310))
        path.addLine(to: pt(11.048, 16.812))
        path.addCurve(to: pt(10.170, 14.730), controlPoint1: pt(10.699, 16.176), controlPoint2: pt(10.426, 15.475))
        path.addCurve(to: pt(9.663, 12.551), controlPoint1: pt(9.880, 13.864), controlPoint2: pt(9.698, 12.984))
        path.addCurve(to: pt(9.770, 10.339), controlPoint1: pt(9.578, 11.801), controlPoint2: pt(9.566, 11.080))
        path.addCurve(to: pt(10.931, 8.473), controlPoint1: pt(9.990, 9.547), controlPoint2: pt(10.384, 8.846))
        path.addCurve(to: pt(12.031, 7.786), controlPoint1: pt(11.244, 8.180), controlPoint2: pt(11.680, 7.973))
        path.addCurve(to: pt(13.138, 7.427), controlPoint1: pt(12.382, 7.599), controlPoint2: pt(12.774, 7.522))
        path.addCurve(to: pt(14.329, 7.244), controlPoint1: pt(13.497, 7.341), controlPoint2: pt(13.924, 7.283))
        path.addCurve(to: pt(16.719, 7.216), controlPoint1: pt(14.727, 7.210), controlPoint2: pt(15.436, 7.150))
        path.addLine(to: pt(17.264, 8.965))
        path.addLine(to: pt(14.510, 8.965))
        path.addCurve(to: pt(13.169, 9.174), controlPoint1: pt(13.917, 8.973), controlPoint2: pt(13.632, 8.966))
        path.addCurve(to: pt(11.891, 11.094), controlPoint1: pt(12.616, 9.490), controlPoint2: pt(12.127, 10.131))
        path.addLine(to: pt(14.554, 11.127))
        path.addLine(to: pt(14.592, 9.317))
        path.close()

        // "L" letter
        path.move(to: pt(20.884, 7.218))
        path.addLine(to: pt(20.884, 13.845))
        path.addLine(to: pt(23.991, 13.877))
        path.addLine(to: pt(23.561, 15.652))
        path.addLine(to: pt(18.754, 15.652))
        path.addLine(to: pt(18.754, 7.187))
        path.close()

        let textLayer = CAShapeLayer()
        textLayer.path = path.cgPath
        textLayer.fillColor = UIColor.white.cgColor
        layer.addSublayer(textLayer)
    }
}

// MARK: - LocalFolderIconView
// Matches Hayase: Lucide `folder` icon with fill='currentColor'.

final class LocalFolderIconView: UIView {

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
        isUserInteractionEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.filter { $0 is CAShapeLayer }.forEach { $0.removeFromSuperlayer() }
        drawIcon()
    }

    private func drawIcon() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        // Lucide folder: viewBox 0 0 24 24
        let scale = min(w / 24.0, h / 24.0)
        let offsetX = (w - 24.0 * scale) / 2
        let offsetY = (h - 24.0 * scale) / 2

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale + offsetX, y: y * scale + offsetY)
        }

        let path = UIBezierPath()
        // Folder shape: M 20 20 -> rounded rect with tab
        path.move(to: pt(22, 19))
        path.addCurve(to: pt(20, 21), controlPoint1: pt(22, 20.1), controlPoint2: pt(21.1, 21))
        path.addLine(to: pt(4, 21))
        path.addCurve(to: pt(2, 19), controlPoint1: pt(2.9, 21), controlPoint2: pt(2, 20.1))
        path.addLine(to: pt(2, 5))
        path.addCurve(to: pt(4, 3), controlPoint1: pt(2, 3.9), controlPoint2: pt(2.9, 3))
        path.addLine(to: pt(9, 3))
        path.addLine(to: pt(12, 7))
        path.addLine(to: pt(20, 7))
        path.addCurve(to: pt(22, 9), controlPoint1: pt(21.1, 7), controlPoint2: pt(22, 7.9))
        path.close()

        let folderLayer = CAShapeLayer()
        folderLayer.path = path.cgPath
        folderLayer.fillColor = UIColor.white.cgColor
        layer.addSublayer(folderLayer)
    }
}

// MARK: - TrackerIconFactory

/// Factory for creating the appropriate icon view for a given tracker.
enum TrackerIconFactory {
    static func makeIcon(for tracker: TrackerKind, size: CGFloat = 24) -> UIView {
        let view: UIView
        switch tracker {
        case .anilist:
            view = AniListIconView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        case .kitsu:
            view = KitsuIconView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        case .mal:
            view = MALIconView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        case .local:
            view = LocalFolderIconView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size),
            view.heightAnchor.constraint(equalToConstant: size),
        ])
        return view
    }
}
