// Mirrors svelte-sonner@0.3.28 Icon.svelte: exact 20px SVG paths, even-odd fills.
import UIKit

enum SonnerToastIcon {
    /// Sonner Icon.svelte's filled 20x20 error glyph, not Lucide's outlined circle-alert.
    static let errorIcon: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
        let path = UIBezierPath(cgPath: SVGPath.path("M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-8-5a.75.75 0 01.75.75v4.5a.75.75 0 01-1.5 0v-4.5A.75.75 0 0110 5zm0 10a1 1 0 100-2 1 1 0 000 2z"))
        path.usesEvenOddFillRule = true
        UIColor.white.setFill()
        path.fill()
    }.withRenderingMode(.alwaysTemplate)

    /// The matching filled circle/check from svelte-sonner@0.3.28 Icon.svelte.
    static let successIcon: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
        let path = UIBezierPath(cgPath: SVGPath.path("M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"))
        path.usesEvenOddFillRule = true
        UIColor.white.setFill()
        path.fill()
    }.withRenderingMode(.alwaysTemplate)
}
