import UIKit
import CoreText

extension UIFont {
    // wght axis identifier (ASCII 'w','g','h','t' as UInt32)
    private static let nunitoWeightAxisID: Int = 2003265652

    static func nunito(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let weightValue = nunitoWeightValue(for: weight)
        let baseDescriptor = UIFontDescriptor(fontAttributes: [
            .family: "Nunito"
        ])
        let variationDescriptor = baseDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                NSNumber(value: nunitoWeightAxisID): NSNumber(value: Double(weightValue))
            ]
        ])
        let font = UIFont(descriptor: variationDescriptor, size: size)
        // If Nunito failed to load, font family will not be Nunito — fall back to system font
        guard font.familyName == "Nunito" else {
            return .systemFont(ofSize: size, weight: weight)
        }
        return font
    }

    private static func nunitoWeightValue(for weight: UIFont.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: return 200
        case .thin:       return 200
        case .light:      return 300
        case .regular:    return 400
        case .medium:     return 500
        case .semibold:   return 600
        case .bold:       return 700
        case .heavy:      return 800
        case .black:      return 900
        default:          return 400
        }
    }
}
