import UIKit

/// Thread/comment styling around the shared interface-compatible renderer.
final class AniListShadowView: AniListRichTextView {
    override init(html: String?, kind: Kind = .thread) { super.init(html: html, kind: kind) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
