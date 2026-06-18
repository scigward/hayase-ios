import UIKit
import LucideIcons

enum HayaseIcon {
    static func image(_ systemName: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        let lucideId = lucideID(for: systemName)
        let image = (UIImage(lucideId: lucideId) ?? UIImage(lucideId: "circle-question-mark"))?.withRenderingMode(.alwaysTemplate)
        guard let configuration else { return image }
        return image?.withConfiguration(configuration)
    }

    private static func lucideID(for systemName: String) -> String {
        switch systemName {
        case "airplayvideo":
            return "airplay"
        case "arrow.down.circle", "arrow.down.circle.fill":
            return "circle-arrow-down"
        case "arrow.down":
            return "download"
        case "arrow.triangle.2.circlepath":
            return "refresh-cw"
        case "arrow.up":
            return "upload"
        case "arrow.up.right.square":
            return "external-link"
        case "arrowshape.turn.up.right":
            return "share-2"
        case "backward.end.fill":
            return "skip-back"
        case "bolt":
            return "bolt"
        case "books.vertical.fill":
            return "library-big"
        case "calendar", "calendar.badge.clock":
            return "calendar-days"
        case "checkmark":
            return "check"
        case "checkmark.seal.fill":
            return "badge-check"
        case "chevron.left":
            return "chevron-left"
        case "chevron.left.forwardslash.chevron.right":
            return "git-branch"
        case "chevron.right":
            return "chevron-right"
        case "clapperboard.fill":
            return "clapperboard"
        case "clock":
            return "clock"
        case "doc.fill":
            return "file"
        case "door.left.hand.open":
            return "door-open"
        case "ellipsis":
            return "ellipsis"
        case "folder.fill":
            return "folder"
        case "forward.end.fill":
            return "skip-forward"
        case "film":
            return "film"
        case "gearshape", "gearshape.fill":
            return "settings"
        case "globe":
            return "globe"
        case "heart", "heart.fill":
            return "heart"
        case "house", "house.fill":
            return "house"
        case "internaldrive":
            return "hard-drive"
        case "link":
            return "link"
        case "magnifyingglass", "magnifyingglass.circle.fill":
            return "search"
        case "minus.circle":
            return "circle-minus"
        case "network":
            return "network"
        case "nosign":
            return "ban"
        case "paperplane.fill":
            return "send-horizontal"
        case "pause.fill":
            return "pause"
        case "pencil.line":
            return "pen-line"
        case "person.2", "person.2.fill":
            return "users"
        case "person.badge.plus":
            return "user-plus"
        case "photo.on.rectangle.angled":
            return "image"
        case "play.circle.fill":
            return "circle-play"
        case "play.fill":
            return "play"
        case "plus":
            return "plus"
        case "shippingbox":
            return "package"
        case "slider.horizontal.3":
            return "sliders-horizontal"
        case "star.fill":
            return "star"
        case "timer":
            return "timer"
        case "trash":
            return "trash-2"
        case "tv":
            return "tv"
        case "wifi":
            return "wifi"
        case "xmark", "xmark.circle.fill":
            return "x"
        default:
            return systemName
        }
    }
}

extension UIImage {
    static func hayaseIcon(_ systemName: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        HayaseIcon.image(systemName, withConfiguration: configuration)
    }
}
