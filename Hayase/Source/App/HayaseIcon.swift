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
            drawFilledIcon(lucideId, in: cg)
            cg.restoreGState()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private static func drawFilledIcon(_ lucideId: String, in cg: CGContext) {
        switch lucideId {
        case "play":
            filledPlayPath().fill()
        case "pause":
            UIBezierPath(roundedRect: CGRect(x: 6, y: 4, width: 4, height: 16), cornerRadius: 1).fill()
            UIBezierPath(roundedRect: CGRect(x: 14, y: 4, width: 4, height: 16), cornerRadius: 1).fill()
        case "skip-back":
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: 19, y: 4))
            triangle.addLine(to: CGPoint(x: 9, y: 12))
            triangle.addLine(to: CGPoint(x: 19, y: 20))
            triangle.close()
            triangle.fill()
            strokeLine(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 19), width: 1)
        case "skip-forward":
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: 5, y: 4))
            triangle.addLine(to: CGPoint(x: 15, y: 12))
            triangle.addLine(to: CGPoint(x: 5, y: 20))
            triangle.close()
            triangle.fill()
            strokeLine(from: CGPoint(x: 19, y: 5), to: CGPoint(x: 19, y: 19), width: 1)
        case "fast-forward":
            filledTriangle(points: [
                CGPoint(x: 13, y: 19),
                CGPoint(x: 22, y: 12),
                CGPoint(x: 13, y: 5),
            ])
            filledTriangle(points: [
                CGPoint(x: 2, y: 19),
                CGPoint(x: 11, y: 12),
                CGPoint(x: 2, y: 5),
            ])
        case "rewind":
            filledTriangle(points: [
                CGPoint(x: 11, y: 19),
                CGPoint(x: 2, y: 12),
                CGPoint(x: 11, y: 5),
            ])
            filledTriangle(points: [
                CGPoint(x: 22, y: 19),
                CGPoint(x: 13, y: 12),
                CGPoint(x: 22, y: 5),
            ])
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
            star.fill()
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
            heart.move(to: CGPoint(x: 12, y: 21))
            heart.addCurve(to: CGPoint(x: 5, y: 14), controlPoint1: CGPoint(x: 10, y: 19.1), controlPoint2: CGPoint(x: 5, y: 16.2))
            heart.addCurve(to: CGPoint(x: 2, y: 8.5), controlPoint1: CGPoint(x: 3.1, y: 12.1), controlPoint2: CGPoint(x: 2, y: 10.4))
            heart.addCurve(to: CGPoint(x: 7.5, y: 3), controlPoint1: CGPoint(x: 2, y: 5.4), controlPoint2: CGPoint(x: 4.4, y: 3))
            heart.addCurve(to: CGPoint(x: 12, y: 5), controlPoint1: CGPoint(x: 9.3, y: 3), controlPoint2: CGPoint(x: 10.5, y: 3.6))
            heart.addCurve(to: CGPoint(x: 16.5, y: 3), controlPoint1: CGPoint(x: 13.5, y: 3.6), controlPoint2: CGPoint(x: 14.7, y: 3))
            heart.addCurve(to: CGPoint(x: 22, y: 8.5), controlPoint1: CGPoint(x: 19.6, y: 3), controlPoint2: CGPoint(x: 22, y: 5.4))
            heart.addCurve(to: CGPoint(x: 19, y: 14), controlPoint1: CGPoint(x: 22, y: 10.4), controlPoint2: CGPoint(x: 20.9, y: 12.1))
            heart.addCurve(to: CGPoint(x: 12, y: 21), controlPoint1: CGPoint(x: 19, y: 16.2), controlPoint2: CGPoint(x: 14, y: 19.1))
            heart.close()
            heart.fill()
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
        path.move(to: CGPoint(x: 6, y: 3))
        path.addLine(to: CGPoint(x: 20, y: 12))
        path.addLine(to: CGPoint(x: 6, y: 21))
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

    private static func filledTriangle(points: [CGPoint]) {
        guard let first = points.first else { return }
        let path = UIBezierPath()
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        path.fill()
    }
}

extension UIImage {
    static func hayaseIcon(_ lucideId: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        HayaseIcon.image(lucideId, withConfiguration: configuration)
    }

    static func hayaseFilledIcon(_ lucideId: String, pointSize: CGFloat = 24) -> UIImage? {
        HayaseIcon.filledImage(lucideId, pointSize: pointSize)
    }
}
