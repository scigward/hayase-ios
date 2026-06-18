import UIKit
import LucideIcons

enum HayaseIcon {
    static func image(_ lucideId: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        let image = (UIImage(lucideId: lucideId) ?? UIImage(lucideId: "circle-question-mark"))?.withRenderingMode(.alwaysTemplate)
        guard let configuration else { return image }
        return image?.withConfiguration(configuration)
    }
}

extension UIImage {
    static func hayaseIcon(_ lucideId: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        HayaseIcon.image(lucideId, withConfiguration: configuration)
    }
}
