import UIKit

extension UIFont {
    // 'wght' axis tag as UInt32 big-endian (w=0x77, g=0x67, h=0x68, t=0x74)
    private static let nunitoWeightAxisTag = NSNumber(value: UInt32(0x77676874))

    static func nunito(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let weightValue = nunitoWeightValue(for: weight)
        let baseDescriptor = UIFontDescriptor(fontAttributes: [.family: "Nunito"])
        // "NSCTFontVariationAttribute" is UIKit's canonical variation key; it is mapped
        // internally to kCTFontVariationAttribute ("CTFontVariation") when UIKit creates
        // the underlying CTFont. Using the CoreText key directly on a UIFontDescriptor would
        // be silently ignored, causing all text to render at the default weight (ExtraLight/200).
        let variationKey = UIFontDescriptor.AttributeName(rawValue: "NSCTFontVariationAttribute")
        let variationDescriptor = baseDescriptor.addingAttributes([
            variationKey: [nunitoWeightAxisTag: NSNumber(value: Double(weightValue))]
        ])
        let font = UIFont(descriptor: variationDescriptor, size: size)
        // If Nunito failed to register (e.g., font file missing), fall back to system font
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
