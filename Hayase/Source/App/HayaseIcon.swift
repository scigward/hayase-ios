import UIKit
import LucideIcons

enum HayaseIcon {
    static func image(_ lucideId: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        let image = (UIImage(lucideId: lucideId) ?? UIImage(lucideId: "circle-question-mark"))?.withRenderingMode(.alwaysTemplate)
        guard let configuration else { return image }
        return image?.withConfiguration(configuration)
    }

    static func filledImage(_ lucideId: String, pointSize: CGFloat = 24) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize))
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.scaleBy(x: pointSize / 24, y: pointSize / 24)
            UIColor.white.setFill()
            UIColor.white.setStroke()
            drawFilledIcon(lucideId, pointSize: pointSize, in: cg)
            cg.restoreGState()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private static func drawFilledIcon(_ lucideId: String, pointSize: CGFloat, in cg: CGContext) {
        switch lucideId {
        case "play":
            filledPath(filledPlayPath(), strokeWidth: 0)
        case "pause":
            filledPath(UIBezierPath(roundedRect: CGRect(x: 6, y: 4, width: 4, height: 16), cornerRadius: 1), strokeWidth: 1)
            filledPath(UIBezierPath(roundedRect: CGRect(x: 14, y: 4, width: 4, height: 16), cornerRadius: 1), strokeWidth: 1)
        case "skip-back":
            drawSkipBackIcon()
        case "skip-forward":
            drawSkipForwardIcon()
        case "fast-forward":
            drawFastForwardIcon()
        case "rewind":
            drawRewindIcon()
        case "star":
            let star = UIBezierPath()
            [
                CGPoint(x: 12, y: 2),
                CGPoint(x: 15.09, y: 8.26),
                CGPoint(x: 22, y: 9.27),
                CGPoint(x: 17, y: 14.14),
                CGPoint(x: 18.18, y: 21.02),
                CGPoint(x: 12, y: 17.77),
                CGPoint(x: 5.82, y: 21.02),
                CGPoint(x: 7, y: 14.14),
                CGPoint(x: 2, y: 9.27),
                CGPoint(x: 8.91, y: 8.26),
            ].enumerated().forEach { index, point in
                if index == 0 {
                    star.move(to: point)
                } else {
                    star.addLine(to: point)
                }
            }
            star.close()
            filledPath(star, strokeWidth: 2)
        case "folder":
            let folder = UIBezierPath()
            folder.move(to: CGPoint(x: 2, y: 6))
            folder.addQuadCurve(to: CGPoint(x: 4, y: 4), controlPoint: CGPoint(x: 2, y: 4.9))
            folder.addLine(to: CGPoint(x: 8, y: 4))
            folder.addQuadCurve(to: CGPoint(x: 9.7, y: 4.9), controlPoint: CGPoint(x: 9.1, y: 4))
            folder.addLine(to: CGPoint(x: 10.9, y: 6.1))
            folder.addQuadCurve(to: CGPoint(x: 12.5, y: 7), controlPoint: CGPoint(x: 11.5, y: 7))
            folder.addLine(to: CGPoint(x: 20, y: 7))
            folder.addQuadCurve(to: CGPoint(x: 22, y: 9), controlPoint: CGPoint(x: 22, y: 7.9))
            folder.addLine(to: CGPoint(x: 22, y: 18))
            folder.addQuadCurve(to: CGPoint(x: 20, y: 20), controlPoint: CGPoint(x: 22, y: 20))
            folder.addLine(to: CGPoint(x: 4, y: 20))
            folder.addQuadCurve(to: CGPoint(x: 2, y: 18), controlPoint: CGPoint(x: 2, y: 20))
            folder.close()
            folder.fill()
        case "badge-check":
            let badge = UIBezierPath()
            [
                CGPoint(x: 12, y: 2),
                CGPoint(x: 15, y: 4.5),
                CGPoint(x: 18.8, y: 4.2),
                CGPoint(x: 19.5, y: 8),
                CGPoint(x: 22, y: 12),
                CGPoint(x: 19.5, y: 16),
                CGPoint(x: 18.8, y: 19.8),
                CGPoint(x: 15, y: 19.5),
                CGPoint(x: 12, y: 22),
                CGPoint(x: 9, y: 19.5),
                CGPoint(x: 5.2, y: 19.8),
                CGPoint(x: 4.5, y: 16),
                CGPoint(x: 2, y: 12),
                CGPoint(x: 4.5, y: 8),
                CGPoint(x: 5.2, y: 4.2),
                CGPoint(x: 9, y: 4.5),
            ].enumerated().forEach { index, point in
                if index == 0 {
                    badge.move(to: point)
                } else {
                    badge.addLine(to: point)
                }
            }
            badge.close()
            badge.fill()

            cg.saveGState()
            cg.setBlendMode(.clear)
            UIColor.white.setStroke()
            let check = UIBezierPath()
            check.move(to: CGPoint(x: 8, y: 12.2))
            check.addLine(to: CGPoint(x: 10.8, y: 15))
            check.addLine(to: CGPoint(x: 16.5, y: 9))
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.lineWidth = 2.2
            check.stroke()
            cg.restoreGState()
        case "heart":
            let heart = UIBezierPath()
            heart.move(to: CGPoint(x: 19, y: 14))
            heart.addCurve(to: CGPoint(x: 22, y: 8.5),
                           controlPoint1: CGPoint(x: 20.49, y: 12.54),
                           controlPoint2: CGPoint(x: 22, y: 10.79))
            heart.addCurve(to: CGPoint(x: 16.5, y: 3),
                           controlPoint1: CGPoint(x: 22, y: 5.46),
                           controlPoint2: CGPoint(x: 19.54, y: 3))
            heart.addCurve(to: CGPoint(x: 12, y: 5),
                           controlPoint1: CGPoint(x: 14.74, y: 3),
                           controlPoint2: CGPoint(x: 13.5, y: 3.5))
            heart.addCurve(to: CGPoint(x: 7.5, y: 3),
                           controlPoint1: CGPoint(x: 10.5, y: 3.5),
                           controlPoint2: CGPoint(x: 9.26, y: 3))
            heart.addCurve(to: CGPoint(x: 2, y: 8.5),
                           controlPoint1: CGPoint(x: 4.46, y: 3),
                           controlPoint2: CGPoint(x: 2, y: 5.46))
            heart.addCurve(to: CGPoint(x: 5, y: 14),
                           controlPoint1: CGPoint(x: 2, y: 10.8),
                           controlPoint2: CGPoint(x: 3.51, y: 12.54))
            heart.addLine(to: CGPoint(x: 12, y: 21))
            heart.close()
            filledPath(heart, strokeWidth: 2)
        case "bookmark":
            let bookmark = UIBezierPath()
            bookmark.move(to: CGPoint(x: 5, y: 21))
            bookmark.addLine(to: CGPoint(x: 5, y: 5))
            bookmark.addQuadCurve(to: CGPoint(x: 7, y: 3), controlPoint: CGPoint(x: 5, y: 3.9))
            bookmark.addLine(to: CGPoint(x: 17, y: 3))
            bookmark.addQuadCurve(to: CGPoint(x: 19, y: 5), controlPoint: CGPoint(x: 19, y: 3.9))
            bookmark.addLine(to: CGPoint(x: 19, y: 21))
            bookmark.addLine(to: CGPoint(x: 12, y: 17))
            bookmark.close()
            bookmark.fill()
        default:
            image(lucideId)?.draw(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        }
    }

    private static func filledPlayPath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 22.99, y: 11.7773))
        path.addCurve(to: CGPoint(x: 21.4859, y: 9.39398),
                      controlPoint1: CGPoint(x: 22.9219, y: 10.8388),
                      controlPoint2: CGPoint(x: 22.4205, y: 9.92777))
        path.addLine(to: CGPoint(x: 7.48782, y: 1.39936))
        path.addCurve(to: CGPoint(x: 3, y: 4.00443),
                      controlPoint1: CGPoint(x: 5.48785, y: 0.25713),
                      controlPoint2: CGPoint(x: 3, y: 1.70127))
        path.addLine(to: CGPoint(x: 3, y: 19.9937))
        path.addCurve(to: CGPoint(x: 7.48781, y: 22.5988),
                      controlPoint1: CGPoint(x: 3, y: 22.2968),
                      controlPoint2: CGPoint(x: 5.48785, y: 23.741))
        path.addLine(to: CGPoint(x: 21.4859, y: 14.6041))
        path.addCurve(to: CGPoint(x: 22.99, y: 12.2208),
                      controlPoint1: CGPoint(x: 22.4205, y: 14.0703),
                      controlPoint2: CGPoint(x: 22.9219, y: 13.1593))
        path.addCurve(to: CGPoint(x: 22.99, y: 11.7773),
                      controlPoint1: CGPoint(x: 23.0226, y: 12.0751),
                      controlPoint2: CGPoint(x: 23.0226, y: 11.9231))
        path.close()
        return path
    }

    private static func drawSkipBackIcon() {
        filledPath(roundedSkipTriangle(direction: -1), strokeWidth: 1)
        strokeLine(from: CGPoint(x: 3, y: 4), to: CGPoint(x: 3, y: 20), width: 2)
    }

    private static func drawSkipForwardIcon() {
        filledPath(roundedSkipTriangle(direction: 1), strokeWidth: 1)
        strokeLine(from: CGPoint(x: 21, y: 4), to: CGPoint(x: 21, y: 20), width: 2)
    }

    private static func drawFastForwardIcon() {
        drawSeekIcon(paths: [
            roundedSeekTriangle(baseX: 2, direction: 1),
            roundedSeekTriangle(baseX: 12, direction: 1),
        ])
    }

    private static func drawRewindIcon() {
        drawSeekIcon(paths: [
            roundedSeekTriangle(baseX: 12, direction: -1),
            roundedSeekTriangle(baseX: 22, direction: -1),
        ])
    }

    private static func drawSeekIcon(paths: [UIBezierPath]) {
        let strokePath = UIBezierPath()
        paths.forEach { path in
            path.lineJoinStyle = .round
            path.fill()
            strokePath.append(path)
        }
        strokePath.lineJoinStyle = .round
        strokePath.lineCapStyle = .round
        strokePath.lineWidth = 2
        strokePath.stroke()
    }

    private static func roundedSeekTriangle(baseX: CGFloat, direction: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let tipX = baseX + direction * 9.412
        let shoulderX = baseX + direction * 3.412
        let controlX1 = baseX + direction * 0.489
        let controlX2 = baseX + direction * 1.235
        let controlX3 = baseX + direction * 1.984
        let controlX4 = baseX + direction * 2.844
        let tipControlX = tipX - direction * 0.37

        path.move(to: CGPoint(x: baseX, y: 6))
        path.addCurve(to: CGPoint(x: controlX2, y: 4.151),
                      controlPoint1: CGPoint(x: baseX, y: 5.193),
                      controlPoint2: CGPoint(x: controlX1, y: 4.464))
        path.addCurve(to: CGPoint(x: shoulderX, y: 4.588),
                      controlPoint1: CGPoint(x: controlX3, y: 3.844),
                      controlPoint2: CGPoint(x: controlX4, y: 4.016))
        path.addLine(to: CGPoint(x: tipX, y: 10.59))
        path.addCurve(to: CGPoint(x: tipX, y: 13.41),
                      controlPoint1: CGPoint(x: tipControlX, y: 11.36),
                      controlPoint2: CGPoint(x: tipControlX, y: 12.64))
        path.addLine(to: CGPoint(x: shoulderX, y: 19.412))
        path.addCurve(to: CGPoint(x: controlX2, y: 19.849),
                      controlPoint1: CGPoint(x: controlX4, y: 19.984),
                      controlPoint2: CGPoint(x: controlX3, y: 20.156))
        path.addCurve(to: CGPoint(x: baseX, y: 18),
                      controlPoint1: CGPoint(x: controlX1, y: 19.54),
                      controlPoint2: CGPoint(x: baseX, y: 18.807))
        path.close()
        return path
    }

    private static func roundedSkipTriangle(direction: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let baseX: CGFloat = direction > 0 ? 3 : 21
        let topShoulderX: CGFloat = baseX + direction * 3.031
        let tipX: CGFloat = baseX + direction * 14
        let lowerShoulderX: CGFloat = topShoulderX

        path.move(to: CGPoint(x: topShoulderX, y: 4.287))
        path.addCurve(to: CGPoint(x: baseX + direction * 1.016, y: 4.26),
                      controlPoint1: CGPoint(x: baseX + direction * 2.412, y: 3.917),
                      controlPoint2: CGPoint(x: baseX + direction * 1.64, y: 3.907))
        path.addCurve(to: CGPoint(x: baseX, y: 6),
                      controlPoint1: CGPoint(x: baseX + direction * 0.385, y: 4.615),
                      controlPoint2: CGPoint(x: baseX, y: 5.281))
        path.addLine(to: CGPoint(x: baseX, y: 18))
        path.addCurve(to: CGPoint(x: baseX + direction * 1.016, y: 19.74),
                      controlPoint1: CGPoint(x: baseX, y: 18.719),
                      controlPoint2: CGPoint(x: baseX + direction * 0.385, y: 19.385))
        path.addCurve(to: CGPoint(x: lowerShoulderX, y: 19.713),
                      controlPoint1: CGPoint(x: baseX + direction * 1.64, y: 20.093),
                      controlPoint2: CGPoint(x: baseX + direction * 2.412, y: 20.083))
        path.addLine(to: CGPoint(x: baseX + direction * 13.027, y: 13.713))
        path.addLine(to: CGPoint(x: baseX + direction * 13.027, y: 13.719))
        path.addCurve(to: CGPoint(x: tipX, y: 12),
                      controlPoint1: CGPoint(x: baseX + direction * 13.631, y: 13.355),
                      controlPoint2: CGPoint(x: tipX, y: 12.703))
        path.addCurve(to: CGPoint(x: baseX + direction * 13.031, y: 10.287),
                      controlPoint1: CGPoint(x: tipX, y: 11.297),
                      controlPoint2: CGPoint(x: baseX + direction * 13.631, y: 10.645))
        path.close()
        return path
    }

    private static func strokeLine(from start: CGPoint, to end: CGPoint, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func filledPath(_ path: UIBezierPath, strokeWidth: CGFloat) {
        path.lineJoinStyle = .round
        path.fill()
        guard strokeWidth > 0 else { return }
        path.lineWidth = strokeWidth
        path.stroke()
    }
}

extension UIImage {
    static func hayaseIcon(_ lucideId: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        HayaseIcon.image(lucideId, withConfiguration: configuration)
    }

    static func hayaseIcon(_ lucideId: String, pointSize: CGFloat) -> UIImage? {
        guard let image = HayaseIcon.image(lucideId) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize))
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
        }.withRenderingMode(.alwaysTemplate)
    }

    static func hayaseFilledIcon(_ lucideId: String, pointSize: CGFloat = 24) -> UIImage? {
        HayaseIcon.filledImage(lucideId, pointSize: pointSize)
    }
}
