import UIKit
import SwiftSoup

/// Profile descriptions share parsing with forums, but scroll at the web's 200pt cap.
final class ProfileShadowView: AniListRichTextView {
    static let maxHeight: CGFloat = 200
    init(html: String?) { super.init(html: html, kind: .profile) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func estimatedHeight(for html: String?, width: CGFloat) -> CGFloat {
        let text = html ?? "No user description"
        if text.range(of: #"(?i)<|img\s|img\(|youtube|webm|~!"#, options: .regularExpression) != nil {
            return maxHeight
        }
        let plain = (try? SwiftSoup.parseBodyFragment(text).text()) ?? text
        let rect = (plain as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.nunito(ofSize: 14, weight: .regular)], context: nil)
        return min(max(ceil(rect.height), 20) + 16, maxHeight)
    }
}
