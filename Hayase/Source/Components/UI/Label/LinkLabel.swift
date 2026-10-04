//
//  LinkLabel.swift
//  Hayase
//
//  Mirrors: an `<a href>` inside a line of text. Each link is an element for D-pad navigation (a view over the
//  text it is), it takes a tap, and it is underlined while the pointer is over it (`hover:underline`).
//

import UIKit

final class LinkLabel: UILabel {
    struct Link {
        let range: NSRange
        let action: () -> Void
    }

    var links: [Link] = [] {
        didSet { rebuildLinkViews() }
    }

    private var linkViews: [UIView] = []
    private var hoveredLink: Int?
    private var restingText: NSAttributedString?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        numberOfLines = 0
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The text that is set is the text at rest: what the pointer underlines is shown in its place and goes with it
    override var attributedText: NSAttributedString? {
        didSet {
            restingText = attributedText
            hoveredLink = nil
        }
    }

    // MARK: - Where the links are

    override func layoutSubviews() {
        super.layoutSubviews()
        for (link, view) in zip(links, linkViews) {
            let box = boxes(of: link).reduce(CGRect.null) { $0.union($1) }
            view.frame = box.isNull ? .zero : box
        }
    }

    private func rebuildLinkViews() {
        linkViews.forEach { $0.removeFromSuperview() }
        linkViews = links.map { link in
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.onDPadClick = link.action
            addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    /// The rectangles of the text of a link, one for each line
    private func boxes(of link: Link) -> [CGRect] {
        guard let text = restingText ?? attributedText, bounds.width > 0 else { return [] }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        let glyphs = manager.glyphRange(forCharacterRange: link.range, actualCharacterRange: nil)
        var boxes: [CGRect] = []
        manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                        in: container) { rect, _ in boxes.append(rect) }
        return boxes
    }

    private func link(at point: CGPoint) -> Int? {
        links.indices.first { index in boxes(of: links[index]).contains { $0.contains(point) } }
    }

    // MARK: - Tap and hover

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let index = link(at: recognizer.location(in: self)) else { return }
        links[index].action()
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        let index = recognizer.state == .began || recognizer.state == .changed
            ? link(at: recognizer.location(in: self)) : nil
        guard index != hoveredLink, let resting = restingText ?? attributedText else { return }
        hoveredLink = index
        let shown = NSMutableAttributedString(attributedString: resting)
        if let index { shown.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: links[index].range) }
        super.attributedText = shown
    }
}
