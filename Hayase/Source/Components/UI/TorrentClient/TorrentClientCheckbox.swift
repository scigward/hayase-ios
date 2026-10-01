// Mirrors interface checkbox.svelte (18pt border box, Radix Check at 14pt).
import UIKit

final class TorrentClientCheckbox: UIButton {
    private let checkbox = UIView()
    private let checkmark = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        checkbox.isUserInteractionEnabled = false
        checkbox.layer.cornerRadius = 4
        checkbox.layer.borderWidth = 1
        checkbox.layer.borderColor = UIColor.HayaseTheme.primary.cgColor
        checkbox.layer.shadowColor = UIColor.black.cgColor
        checkbox.layer.shadowOpacity = 0.1
        checkbox.layer.shadowRadius = 1.5
        checkbox.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(checkbox)
        checkmark.image = TorrentClientRadixIcons.check
        checkmark.isUserInteractionEnabled = false
        checkmark.tintColor = UIColor.HayaseTheme.primaryForeground
        checkbox.addSubview(checkmark)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 18, height: 18) }
    override var isSelected: Bool { didSet { updateAppearance() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        checkbox.frame = CGRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)
        checkmark.frame = CGRect(x: 2, y: 2, width: 14, height: 14)
    }

    private func updateAppearance() {
        checkbox.backgroundColor = isSelected ? UIColor.HayaseTheme.primary : .clear
        checkmark.isHidden = !isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        accessibilityValue = isSelected ? "Selected" : "Not selected"
    }
}

/// Exact upstream Radix SVG geometry, also used by columnheader.svelte.
enum TorrentClientRadixIcons {
    static let check = render("M10.6015 3.90815C10.7903 3.61941 11.1779 3.53792 11.4667 3.72651C11.7555 3.91533 11.837 4.30288 11.6484 4.59175L7.39837 11.0917C7.29822 11.2449 7.13558 11.3469 6.95404 11.3701C6.77251 11.3932 6.58945 11.3359 6.45404 11.2128L3.70404 8.71284L3.62005 8.61811C3.44857 8.38342 3.4589 8.05252 3.66205 7.82905C3.86511 7.60576 4.19344 7.56371 4.4433 7.71186L4.54584 7.78706L6.75287 9.79292L10.6015 3.90815Z")
    static let arrowUp = render("M7.22457 2.08224C7.41865 1.95407 7.68261 1.97583 7.85348 2.14669L11.8535 6.14669L11.9179 6.22482C12.0461 6.4189 12.0243 6.68286 11.8535 6.85372C11.6826 7.02459 11.4187 7.04634 11.2246 6.91818L11.1464 6.85372L7.99996 3.70724V12.5002C7.99996 12.7763 7.7761 13.0002 7.49996 13.0002C7.22382 13.0002 6.99996 12.7763 6.99996 12.5002V3.70724L3.85348 6.85372C3.65822 7.04899 3.34171 7.04899 3.14645 6.85372C2.95118 6.65846 2.95118 6.34195 3.14645 6.14669L7.14645 2.14669L7.22457 2.08224Z")
    static let arrowDown = render("M7.22457 2.08224C7.41865 1.95407 7.68261 1.97583 7.85348 2.14669L11.8535 6.14669L11.9179 6.22482C12.0461 6.4189 12.0243 6.68286 11.8535 6.85372C11.6826 7.02459 11.4187 7.04634 11.2246 6.91818L11.1464 6.85372L7.99996 3.70724V12.5002C7.99996 12.7763 7.7761 13.0002 7.49996 13.0002C7.22382 13.0002 6.99996 12.7763 6.99996 12.5002V3.70724L3.85348 6.85372C3.65822 7.04899 3.34171 7.04899 3.14645 6.85372C2.95118 6.65846 2.95118 6.34195 3.14645 6.14669L7.14645 2.14669L7.22457 2.08224Z", flipped: true)

    private static func render(_ data: String, flipped: Bool = false) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14)).image { renderer in
            let context = renderer.cgContext
            context.scaleBy(x: 14 / 15, y: 14 / 15)
            if flipped { context.translateBy(x: 0, y: 15); context.scaleBy(x: 1, y: -1) }
            context.addPath(SVGPath.path(data))
            UIColor.black.setFill()
            context.fillPath()
        }.withRenderingMode(.alwaysTemplate)
    }
}
