//
//  Threads.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/forums/Threads.svelte
//

import UIKit

// MARK: - ThreadBadgeColors

/// `style:background={media.coverImage?.color ?? '#27272a'}` around `text-contrast`. That class reads `--red`,
/// `--green` and `--blue` of the page (`colors(media.coverImage?.color)`, white when the media has no colour), not
/// the background it sits on: a media without a colour has a dark badge with black text.
struct ThreadBadgeColors {
    let background: UIColor
    let text: UIColor

    init(coverColor: String?) {
        if let color = ExtensionSearchViewController.uiColor(fromHex: coverColor) {
            background = color
            text = ExtensionSearchViewController.luminanceContrastColor(for: color)
        } else {
            background = UIColor.HayaseTheme.secondary
            text = ExtensionSearchViewController.luminanceContrastColor(for: .white)
        }
    }
}

// MARK: - ThreadBadgeLabel

/// A category of a thread: `rounded px-3 py-0.5 font-bold`, 9.6px text on a line of 14.4px.
final class ThreadBadgeLabel: UILabel {
    let hPad: CGFloat = 12
    let vPad: CGFloat = 2

    static func make(title: String, colors: ThreadBadgeColors) -> ThreadBadgeLabel {
        let badge = ThreadBadgeLabel()
        badge.attributedText = CSSText.string(title, font: .nunito(ofSize: 9.6, weight: .bold), color: colors.text,
                                              lineHeight: 14.4, lineBreak: .byClipping)
        badge.backgroundColor = colors.background
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        return badge
    }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(width: base.width + hPad * 2, height: base.height + vPad * 2)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: hPad, dy: vPad))
    }
}

// MARK: - ThreadFlex

/// The shrinking of flex items (`flex: 0 1 auto`, `min-width: auto`) that do not fit their row: each gives up room in
/// proportion to its width, and none goes below its min-content width (one that would is kept there and the others
/// give up the rest).
enum ThreadFlex {
    static func shrink(bases: [CGFloat], mins: [CGFloat], into width: CGFloat) -> [CGFloat] {
        var sizes = bases
        var frozen = [Bool](repeating: false, count: bases.count)
        while true {
            let open = bases.indices.filter { !frozen[$0] }
            let taken = bases.indices.filter { frozen[$0] }.reduce(CGFloat(0)) { $0 + sizes[$1] }
            let openBase = open.reduce(CGFloat(0)) { $0 + bases[$1] }
            let free = width - taken - openBase
            guard free < 0, openBase > 0 else {
                for index in open { sizes[index] = bases[index] }
                return sizes
            }
            let targets = open.map { bases[$0] + free * bases[$0] / openBase }
            let tooSmall = open.enumerated().filter { targets[$0.offset] < mins[$0.element] }.map { $0.element }
            if tooSmall.isEmpty {
                for (offset, index) in open.enumerated() { sizes[index] = targets[offset] }
                return sizes
            }
            for index in tooSmall {
                sizes[index] = mins[index]
                frozen[index] = true
            }
        }
    }
}

// MARK: - ThreadBadgeFlowView

/// The categories: `ml-auto inline-flex flex-wrap gap-2 items-end`. They are in a line while the room allows, the rest
/// go on the lines below (`gap-2` between lines too), each at the bottom of its line, and the lines share the height
/// the row gives the container (`align-content: stretch`).
final class ThreadBadgeFlowView: UIView {
    private static let gap: CGFloat = 8
    private var badges: [ThreadBadgeLabel] = []
    private var widths: [CGFloat] = []
    private var badgeHeight: CGFloat = 0

    func setBadges(_ new: [ThreadBadgeLabel]) {
        badges.forEach { $0.removeFromSuperview() }
        badges = new
        widths = new.map { $0.intrinsicContentSize.width }
        badgeHeight = new.first?.intrinsicContentSize.height ?? 0
        for badge in new {
            badge.translatesAutoresizingMaskIntoConstraints = true
            addSubview(badge)
        }
        setNeedsLayout()
    }

    /// The width of all of them in one line
    var maxContentWidth: CGFloat {
        widths.reduce(0, +) + Self.gap * CGFloat(max(0, widths.count - 1))
    }

    /// The width of the widest of them: no less than that
    var minContentWidth: CGFloat {
        widths.max() ?? 0
    }

    private func lines(for width: CGFloat) -> [[Int]] {
        var result: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for index in widths.indices {
            if !current.isEmpty, x + Self.gap + widths[index] > width + 0.01 {
                result.append(current)
                current = []
            }
            x = current.isEmpty ? widths[index] : x + Self.gap + widths[index]
            current.append(index)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    func contentHeight(for width: CGFloat) -> CGFloat {
        let count = lines(for: width).count
        return CGFloat(count) * badgeHeight + Self.gap * CGFloat(max(0, count - 1))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rows = lines(for: bounds.width)
        guard !rows.isEmpty else { return }
        let natural = CGFloat(rows.count) * badgeHeight + Self.gap * CGFloat(rows.count - 1)
        let lineHeight = badgeHeight + max(0, bounds.height - natural) / CGFloat(rows.count)
        var y: CGFloat = 0
        for line in rows {
            var x: CGFloat = 0
            for index in line {
                badges[index].frame = CGRect(x: x, y: y + lineHeight - badgeHeight, width: widths[index], height: badgeHeight)
                x += widths[index] + Self.gap
            }
            y += lineHeight + Self.gap
        }
    }
}

// MARK: - ThreadFooterRowView

/// The last row of a card and of the post: `flex w-full justify-between mt-auto text-[9.6px]`. On the left an item
/// that is a few fixed views and the date (`since()`), on the right the categories. When they do not fit together both
/// give up room in proportion to their sizes (`ThreadFlex`), the categories go on more lines and the date on more lines
/// of its own (it cannot be narrower than its longest word), and the row is as tall as the taller of the two.
final class ThreadFooterRowView: UIView {
    enum Alignment { case bottom, center }

    private let topInset: CGFloat
    private let itemSpacing: CGFloat
    private let dateGap: CGFloat
    private let leadingStack = UIStackView()
    private let dateLabel = UILabel()
    private let flowView = ThreadBadgeFlowView()
    private var leadingItems: [UIView] = []
    private var dateText = NSAttributedString()
    private var leadingWidth: NSLayoutConstraint!
    private var leadingHeight: NSLayoutConstraint!
    private var flowWidth: NSLayoutConstraint!
    private var flowHeight: NSLayoutConstraint!
    private var dateHeight: NSLayoutConstraint!
    private var rowHeight: NSLayoutConstraint!
    /// The width of the last measure; before there is one, room for everything in a line.
    private var measuredWidth: CGFloat = 10_000

    /// The height the row would have if nothing cut it
    private(set) var contentHeight: CGFloat = 0
    /// The row is cut here (a card's `max-h-28 overflow-hidden`)
    var maxHeight: CGFloat = .greatestFiniteMagnitude
    /// The row has another height than it had: whatever holds it has to measure again.
    var onContentHeightChange: (() -> Void)?

    /// `topInset` is the `pt-2` of the leading item. `itemSpacing` is between its fixed views and `dateGap` between them
    /// and the date.
    init(alignment: Alignment, topInset: CGFloat, itemSpacing: CGFloat, dateGap: CGFloat) {
        self.topInset = topInset
        self.itemSpacing = itemSpacing
        self.dateGap = dateGap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        leadingStack.axis = .horizontal
        leadingStack.alignment = alignment == .bottom ? .bottom : .center
        leadingStack.spacing = itemSpacing
        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.numberOfLines = 0
        dateLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leadingStack.addArrangedSubview(dateLabel)
        flowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leadingStack)
        addSubview(flowView)

        leadingWidth = leadingStack.widthAnchor.constraint(equalToConstant: 0)
        leadingHeight = leadingStack.heightAnchor.constraint(equalToConstant: 0)
        flowWidth = flowView.widthAnchor.constraint(equalToConstant: 0)
        flowHeight = flowView.heightAnchor.constraint(equalToConstant: 0)
        dateHeight = dateLabel.heightAnchor.constraint(equalToConstant: 0)
        rowHeight = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            leadingStack.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            leadingStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            leadingWidth, leadingHeight,
            flowView.topAnchor.constraint(equalTo: topAnchor),
            flowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            flowWidth, flowHeight,
            dateHeight, rowHeight,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The views before the date, each of its own size
    func setLeadingItems(_ items: [UIView]) {
        leadingItems.forEach { item in
            leadingStack.removeArrangedSubview(item)
            item.removeFromSuperview()
        }
        leadingItems = items
        for (index, item) in items.enumerated() {
            leadingStack.insertArrangedSubview(item, at: index)
        }
        if let last = items.last { leadingStack.setCustomSpacing(dateGap, after: last) }
        update(width: measuredWidth)
    }

    func setContent(date: NSAttributedString, badges: [ThreadBadgeLabel]) {
        dateText = date
        dateLabel.attributedText = date
        flowView.setBadges(badges)
        update(width: measuredWidth)
    }

    private var dateLineHeight: CGFloat {
        guard dateText.length > 0,
              let style = dateText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
              style.maximumLineHeight > 0 else { return 14.4 }
        return style.maximumLineHeight
    }

    private var longestWordWidth: CGFloat {
        guard dateText.length > 0 else { return 0 }
        let attributes = dateText.attributes(at: 0, effectiveRange: nil)
        return dateText.string.split(separator: " ")
            .map { ceil(NSAttributedString(string: String($0), attributes: attributes).size().width) }
            .max() ?? 0
    }

    private func lineCount(width: CGFloat) -> Int {
        guard dateText.length > 0, width > 0 else { return 1 }
        let rect = dateText.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin], context: nil)
        return max(1, Int((rect.height / dateLineHeight).rounded()))
    }

    /// Measures the row for a width: what the leading item and the categories get of it and how tall the row has to be.
    @discardableResult
    func update(width available: CGFloat) -> CGFloat {
        measuredWidth = available
        let visible = leadingItems.filter { !$0.isHidden }
        let sizes = visible.map { $0.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) }
        var fixed: CGFloat = 0
        for size in sizes { fixed += size.width }
        if !visible.isEmpty { fixed += itemSpacing * CGFloat(visible.count - 1) + dateGap }
        let fixedHeight = sizes.map { $0.height }.max() ?? 0

        let leadingBasis = fixed + ceil(dateText.size().width)
        let leadingMin = min(fixed + longestWordWidth, leadingBasis)
        let flowBasis = flowView.maxContentWidth
        let flowMin = min(flowView.minContentWidth, flowBasis)
        let shares = ThreadFlex.shrink(bases: [leadingBasis, flowBasis], mins: [leadingMin, flowMin], into: available)

        let textHeight = CGFloat(lineCount(width: shares[0] - fixed)) * dateLineHeight
        let height = max(topInset + max(fixedHeight, textHeight), flowView.contentHeight(for: shares[1]))

        let before = rowHeight.constant
        leadingWidth.constant = shares[0]
        leadingHeight.constant = max(0, height - topInset)
        dateHeight.constant = textHeight
        flowWidth.constant = shares[1]
        flowHeight.constant = height
        contentHeight = height
        clipsToBounds = maxHeight < .greatestFiniteMagnitude
        rowHeight.constant = min(height, maxHeight)
        if abs(rowHeight.constant - before) > 0.5 { onContentHeightChange?() }
        return height
    }

    override func layoutSubviews() {
        // the width the row really has, which is not always the one it was measured for
        if bounds.width > 0, abs(bounds.width - measuredWidth) > 0.5 {
            update(width: bounds.width)
        }
        super.layoutSubviews()
    }
}

// MARK: - ThreadStatsView

/// The likes, views, replies and lock of a thread: `flex ml-2 leading-none`, 12px icons with `mr-1` and the numbers
/// at the size of the row (12.8px) in `text-secondary-foreground`. The icons and the numbers are items of a row that
/// is as tall as the title beside it, so they sit at its top.
final class ThreadStatsView: UIView {
    private static let fontSize: CGFloat = 12.8
    private let stack = UIStackView()
    private let likesIconView = UIImageView()
    private let likesLabel = UILabel()
    private let viewsLabel = UILabel()
    private let repliesLabel = UILabel()
    private let lockHost = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        stack.axis = .horizontal
        stack.spacing = 8   // `ml-2` of the second and third icon and of the lock
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(makeItem(icon: "heart", label: likesLabel, imageView: likesIconView))
        stack.addArrangedSubview(makeItem(icon: "eye", label: viewsLabel))
        stack.addArrangedSubview(makeItem(icon: "messages-square", label: repliesLabel))

        // `<Lock size='12' class='mr-1 ml-2 text-red-500' />`: its `mr-1` is space after it
        let lock = UIImageView(image: UIImage.hayaseIcon("lock", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)))
        lock.tintColor = UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)
        lock.contentMode = .scaleAspectFit
        lock.translatesAutoresizingMaskIntoConstraints = false
        lockHost.addSubview(lock)
        NSLayoutConstraint.activate([
            lock.topAnchor.constraint(equalTo: lockHost.topAnchor),
            lock.leadingAnchor.constraint(equalTo: lockHost.leadingAnchor),
            lock.widthAnchor.constraint(equalToConstant: 12),
            lock.heightAnchor.constraint(equalToConstant: 12),
            lockHost.widthAnchor.constraint(equalToConstant: 16),
            lockHost.heightAnchor.constraint(equalToConstant: 12),
        ])
        stack.addArrangedSubview(lockHost)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeItem(icon: String, label: UILabel, imageView: UIImageView = UIImageView()) -> UIStackView {
        imageView.image = UIImage.hayaseIcon(icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        imageView.tintColor = UIColor.HayaseTheme.secondaryForeground
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])

        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let item = UIStackView(arrangedSubviews: [imageView, label])
        item.axis = .horizontal
        item.spacing = 4   // `mr-1`
        item.alignment = .top
        return item
    }

    private func text(_ value: Int) -> NSAttributedString {
        CSSText.string("\(value)", font: .nunito(ofSize: Self.fontSize), color: UIColor.HayaseTheme.secondaryForeground,
                       lineHeight: Self.fontSize)   // `leading-none`
    }

    private func heart(filled: Bool) -> UIImage? {
        filled
            ? HayaseIcon.filledImage("heart", pointSize: 12)
            : UIImage.hayaseIcon("heart", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular))
    }

    func configure(likes: Int, views: Int, replies: Int, locked: Bool, liked: Bool = false) {
        likesIconView.image = heart(filled: liked)
        likesLabel.attributedText = text(likes)
        viewsLabel.attributedText = text(views)
        repliesLabel.attributedText = text(replies)
        lockHost.isHidden = !locked
    }

    func updateLikes(count: Int, liked: Bool) {
        likesIconView.image = heart(filled: liked)
        likesLabel.attributedText = text(count)
    }
}

// MARK: - ThreadAvatarView

/// `<Avatar.Root class='size-4 mr-2'>`: a 16px circle with the image, and until it is there (or when it cannot be
/// loaded) `Avatar.Fallback`: `bg-muted`, which is the colour of the card, around the name of the user, clipped to
/// the circle.
final class ThreadAvatarView: UIView {
    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private var task: URLSessionDataTask?
    private var currentURL: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.HayaseTheme.muted
        layer.cornerRadius = 8
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        nameLabel.lineBreakMode = .byClipping
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 16),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Nothing for a thread without a user: the interface draws no avatar then.
    func configure(user: AniListUserSummary?) {
        reset()
        guard let user else {
            isHidden = true
            return
        }
        isHidden = false
        nameLabel.attributedText = CSSText.string(user.name, font: .nunito(ofSize: 9.6),
                                                  color: UIColor.HayaseTheme.secondaryForeground, lineHeight: 14.4,
                                                  lineBreak: .byClipping)
        guard let urlString = user.avatarURL, let url = URL(string: urlString) else { return }
        currentURL = urlString
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.currentURL == urlString else { return }
                self.imageView.image = image
                self.imageView.isHidden = false
                self.nameLabel.isHidden = true
            }
        }
        task?.resume()
    }

    func reset() {
        task?.cancel()
        task = nil
        currentURL = nil
        imageView.image = nil
        imageView.isHidden = true
        nameLabel.attributedText = nil
        nameLabel.isHidden = false
    }
}

// MARK: - ThreadCardView

/// A thread of the list: `Threads.svelte`'s `<a>`, `max-h-28` and as tall as what is in it. A card of the row that
/// is shorter than its neighbour is centred in the row (`place-items-center`).
final class ThreadCardView: SelectableCardView {

    var onTap: ((Int) -> Void)?
    private var threadID: Int = 0

    private let titleLabel = UILabel()
    private let statsView = ThreadStatsView()
    private let avatarView = ThreadAvatarView()
    /// `flex w-full justify-between mt-auto text-[9.6px]`: the avatar (`mr-2`) and the date under `pt-2`, and the
    /// categories, which go on more lines when the card is narrow
    private let footerRow = ThreadFooterRowView(alignment: .bottom, topInset: 8, itemSpacing: 8, dateGap: 8)
    private var heightConstraint: NSLayoutConstraint!

    /// `py-3`, the title (19.2) and its `mb-2`: where the last row starts
    private static let footerTop: CGFloat = 39.2
    private static let maxHeight: CGFloat = 112   // `max-h-28`, which cuts what is below it
    private static let padding: CGFloat = 32      // `px-4`

    init() {
        // Threads.svelte: bg-muted, select:bg-accent
        super.init(restingBackground: UIColor.HayaseTheme.muted,
                   selectedBackground: UIColor.HayaseTheme.accent)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        layer.cornerRadius = 6
        // The select:shadow-lg shadow draws outside the card, so it must not clip.
        clipsToBounds = false

        // an `<a>` says what is in it, and the title has a tooltip that a pointer reaches
        isAccessibilityElement = true
        accessibilityTraits = .link
        titleLabel.isUserInteractionEnabled = true

        titleLabel.numberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statsView.setContentCompressionResistancePriority(.required, for: .horizontal)
        statsView.setContentHuggingPriority(.required, for: .horizontal)

        footerRow.maxHeight = Self.maxHeight - Self.footerTop
        footerRow.onContentHeightChange = { [weak self] in self?.applyHeight() }

        [titleLabel, statsView, footerRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        heightConstraint = heightAnchor.constraint(equalToConstant: Self.footerTop + 24 + 12)
        NSLayoutConstraint.activate([
            heightConstraint,

            // `py-3 px-4`; the title is `mb-2` above the row
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statsView.leadingAnchor, constant: -8),

            // `ml-2 mt-0.5`
            statsView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            statsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            footerRow.topAnchor.constraint(equalTo: topAnchor, constant: Self.footerTop),
            footerRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            footerRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        addGestureRecognizer(tap)
        onDPadClick = { [weak self] in self?.cardTapped() }
    }

    /// As tall as what is in it, up to `max-h-28`, with `py-3` below the last row.
    private func applyHeight() {
        heightConstraint.constant = min(Self.maxHeight, Self.footerTop + footerRow.contentHeight + 12)
    }

    @objc private func cardTapped() {
        onTap?(threadID)
    }

    /// `width` is the width of the card in its grid; the last row is measured for it.
    func configure(with thread: AniListThread, badgeColors: ThreadBadgeColors, width: CGFloat) {
        threadID = thread.id
        titleLabel.attributedText = CSSText.string(thread.title, font: .nunito(ofSize: 12.8, weight: .bold),
                                                   color: UIColor.HayaseTheme.secondaryForeground, lineHeight: 19.2)
        // `<Tooltip.Content>` with the whole title, for a pointer over the title
        titleLabel.attachTooltip(thread.title)
        statsView.configure(likes: thread.likeCount, views: thread.viewCount, replies: thread.replyCount, locked: thread.isLocked)

        avatarView.configure(user: thread.user)
        footerRow.setLeadingItems(thread.user == nil ? [] : [avatarView])
        footerRow.setContent(date: CSSText.string(thread.sinceString, font: .nunito(ofSize: 9.6),
                                                  color: UIColor.HayaseTheme.secondaryForeground, lineHeight: 14.4,
                                                  lineBreak: .byWordWrapping),
                             badges: thread.categories.map { ThreadBadgeLabel.make(title: $0, colors: badgeColors) })
        if width > Self.padding { footerRow.update(width: width - Self.padding) }
        applyHeight()

        accessibilityLabel = ([thread.title, "\(thread.likeCount)", "\(thread.viewCount)", "\(thread.replyCount)",
                               thread.sinceString] + thread.categories).joined(separator: ", ")
    }

    func reset() {
        avatarView.reset()
        avatarView.isHidden = true
        titleLabel.attributedText = nil
        statsView.configure(likes: 0, views: 0, replies: 0, locked: false)
        footerRow.setLeadingItems([])
        footerRow.setContent(date: NSAttributedString(), badges: [])
        accessibilityLabel = nil
        threadID = 0
        onTap = nil
        resetSelectState()
    }
}

// MARK: - ThreadPairCell

/// A row of the grid: `gap-x-10 gap-y-7 place-items-center`, under `pt-3`. The 28 between two rows is split in
/// two, the first row has the 12 of `pt-3` above it and the last has nothing below it: the page buttons follow
/// with their own `py-3`.
final class ThreadPairCell: UITableViewCell, CardOverflowRendering {
    static let reuseID = "ThreadPairCell"

    let leftCard = ThreadCardView()
    let rightCard = ThreadCardView()
    var onTapThread: ((Int) -> Void)?

    private let stack = UIStackView()
    private let rightContainer = UIView()
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center   // `place-items-center`
        stack.spacing = 40
        stack.translatesAutoresizingMaskIntoConstraints = false

        leftCard.translatesAutoresizingMaskIntoConstraints = false
        rightCard.translatesAutoresizingMaskIntoConstraints = false

        rightContainer.addSubview(rightCard)
        stack.addArrangedSubview(leftCard)
        stack.addArrangedSubview(rightContainer)
        contentView.addSubview(stack)

        let top = stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14)
        let bottom = stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        let leading = stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        let trailing = stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        stackTopConstraint = top
        stackBottomConstraint = bottom
        stackLeadingConstraint = leading
        stackTrailingConstraint = trailing

        NSLayoutConstraint.activate([
            top,
            bottom,
            leading,
            trailing,
            rightCard.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            rightCard.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor),
            rightCard.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            rightCard.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
        ])
    }

    func applyPageSideInset(_ sidePad: CGFloat, isFirstRow: Bool, isLastRow: Bool) {
        stackTopConstraint?.constant = isFirstRow ? 12 : 14   // pt-3; later rows split gap-y-7 = 28px
        stackBottomConstraint?.constant = isLastRow ? 0 : -14
        stackLeadingConstraint?.constant = sidePad
        stackTrailingConstraint?.constant = -sidePad
    }

    /// `singleTrack` lays the row out as one full-width column. Otherwise a row
    /// without a right thread keeps its empty second column, as the grid does.
    func configure(left: AniListThread, right: AniListThread?, singleTrack: Bool, badgeColors: ThreadBadgeColors,
                   cardWidth: CGFloat) {
        leftCard.configure(with: left, badgeColors: badgeColors, width: cardWidth)
        leftCard.onTap = { [weak self] id in self?.onTapThread?(id) }

        rightContainer.isHidden = singleTrack
        if let right = right {
            rightCard.configure(with: right, badgeColors: badgeColors, width: cardWidth)
            rightCard.onTap = { [weak self] id in self?.onTapThread?(id) }
            rightCard.isHidden = false
        } else {
            rightCard.reset()
            rightCard.isHidden = true
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        allowCardOverflowRendering()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        allowCardOverflowRendering()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leftCard.reset()
        rightCard.reset()
        rightCard.isHidden = false
        rightContainer.isHidden = false
        onTapThread = nil
    }
}

// MARK: - Thread fetching

extension AnimeDetailViewController {

    /// `$threads.fetching`: the page of the media itself is still on its way, or the page asked for is.
    var threadsFetching: Bool {
        threadsPage == 1 ? recommendationsLoading : threadsPageLoading
    }

    /// `$threads.error?.message`
    var threadsErrorMessage: String? {
        threadsPage == 1 ? animePageErrorDescription : threadsPageError
    }

    /// `count = total === 5000 ? 17 : total`, of the page that is on show: it is 0 until the page is there.
    var threadCount: Int {
        let total = threadPages[threadsPage]?.total ?? 0
        return total == 5000 ? 17 : total
    }

    /// `$threads` of the page on show: its threads, once they are there.
    func applyThreadsPage() {
        threads = threadPages[threadsPage]?.threads ?? []
    }

    /// `setPage` of the `Pagination`: it keeps the page between 1 and the last.
    func setThreadsPage(_ page: Int) {
        let lastPage = Int(ceil(Double(threadCount) / Double(Self.threadsPerPage)))
        let clamped = min(max(1, page), max(1, lastPage))
        guard clamped != threadsPage else { return }
        threadsPage = clamped
        threadsPageError = nil
        threadsPageLoading = false
        applyThreadsPage()
        if clamped > 1, threadPages[clamped] == nil {
            fetchThreadsPage(clamped)
        } else {
            reloadSectionsWithoutAnimation([.threads, .threadPagination])
        }
    }

    static let threadsPerPage = 16

    /// `client.threads(media.id, currentPage)`, for the pages after the first.
    func fetchThreadsPage(_ page: Int) {
        guard let id = routeAnimeID else { return }
        threadsPageLoading = true
        threadsPageError = nil
        reloadSectionsWithoutAnimation([.threads, .threadPagination])

        AniListClient.shared.threadsResult(mediaID: id, page: page, perPage: Self.threadsPerPage) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let answer):
                self.threadPages[page] = (answer.threads, answer.total)
            case .failure(let error):
                NSLog("[AnimeDetail] Threads failed: %@", error.description)
                if self.threadsPage == page { self.threadsPageError = error.description }
            }
            // the page may have been turned meanwhile, and the answer is for the one that was asked
            guard self.threadsPage == page else { return }
            self.threadsPageLoading = false
            self.applyThreadsPage()
            if self.activeSection == .threads {
                self.reloadSectionsWithoutAnimation([.threads, .threadPagination])
            }
        }
    }

    func makeThreadCell(for indexPath: IndexPath) -> UITableViewCell {
        if embeddedThreadID != nil {
            return makeEmbeddedThreadCell()
        }
        if threadsFetching {
            return makeThreadsSkeletonCell()
        }
        if let message = threadsErrorMessage {
            return makeEmptyStateCell(text: "Looks like something went wrong!", loading: false, detail: message)
        }

        if threads.isEmpty {
            return makeEmptyStateCell(
                text: "Looks like there's nothing here yet!",
                loading: false)
        }
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ThreadPairCell.reuseID, for: indexPath) as? ThreadPairCell else {
            return UITableViewCell()
        }
        let cols = threadGridColumnCount
        let rows = (threads.count + cols - 1) / cols
        let leftIdx = indexPath.row * cols
        guard let leftThread = threads[safe: leftIdx] else { return cell }
        let rightThread = cols >= 2 ? threads[safe: leftIdx + 1] : nil
        // the width of a track of the grid: the card is measured for it
        let cardWidth = cols == 1 ? pageGridWidth : (pageGridWidth - Self.threadGap) / 2
        cell.configure(left: leftThread, right: rightThread, singleTrack: cols == 1,
                       badgeColors: ThreadBadgeColors(coverColor: animeItem?.coverColor), cardWidth: cardWidth)
        cell.applyPageSideInset(Self.interfacePageSideInset(for: viewportWidth),
                                isFirstRow: indexPath.row == 0, isLastRow: indexPath.row == rows - 1)
        cell.onTapThread = { [weak self] threadID in
            self?.openThread(id: threadID)
        }
        return cell
    }

    /// The footer of `Threads.svelte`: the range, and the buttons of the pages.
    func makeThreadPaginationCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none

        let footer = ThreadPaginationView()
        footer.noun = "threads"
        footer.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(footer)
        let sidePad = Self.interfacePageSideInset(for: viewportWidth)
        NSLayoutConstraint.activate([
            footer.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            footer.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: sidePad),
            footer.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -sidePad),
        ])
        footer.configure(count: threadCount, perPage: Self.threadsPerPage, currentPage: threadsPage) { [weak self] page in
            self?.setThreadsPage(page)
        }
        return cell
    }

    /// The card is a link to the route of the thread, which the interface opens from the thread it already has.
    private func openThread(id threadID: Int) {
        guard let thread = threads.first(where: { $0.id == threadID }), let animeID = routeAnimeID else { return }
        Router.shared.navigateToAnimeThread(animeID: animeID, threadID: thread.id, title: thread.title,
                                            thread: thread, hostTabIndex: hayaseTabIndex)
    }

    /// The thread as the thread page last had it: the same entry of the list, as the interface's cache keeps one
    /// `Thread` for the list and for the page.
    func updateListedThread(_ thread: AniListThread) {
        for (page, entry) in threadPages {
            guard let index = entry.threads.firstIndex(where: { $0.id == thread.id }) else { continue }
            var listed = entry.threads
            listed[index] = thread
            threadPages[page] = (listed, entry.total)
        }
        applyThreadsPage()
        if activeSection == .threads, embeddedThreadID == nil {
            UIView.performWithoutAnimation {
                tableView.reconfigureRows(at: tableView.indexPathsForVisibleRows?.filter { $0.section == Section.threads.rawValue } ?? [])
            }
        }
    }

    private func makeThreadsSkeletonCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none

        let columns = max(threadColumnCount, 1)
        let rows = (4 + columns - 1) / columns
        let outerStack = UIStackView()
        outerStack.axis = .vertical
        outerStack.spacing = 28
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(outerStack)

        var made = 0
        for _ in 0..<rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = columns > 1 ? 40 : 0
            outerStack.addArrangedSubview(row)

            for _ in 0..<columns {
                if made < 4 {
                    row.addArrangedSubview(makeThreadSkeletonCard())
                } else {
                    row.addArrangedSubview(UIView())
                }
                made += 1
            }
        }

        let sidePad = Self.interfacePageSideInset(for: viewportWidth)

        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),  // pt-3 = 12px
            outerStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            outerStack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: sidePad),
            outerStack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -sidePad),
        ])
        return cell
    }

    private func makeThreadSkeletonCard() -> UIView {
        let card = UIView()
        card.backgroundColor = hayaseCardBackground
        card.layer.cornerRadius = 6
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = HayaseSkeleton.makeBlock(cornerRadius: 4)
        let footer = HayaseSkeleton.makeBlock(cornerRadius: 4)
        card.addSubview(title)
        card.addSubview(footer)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 75),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.widthAnchor.constraint(equalToConstant: 112),
            title.heightAnchor.constraint(equalToConstant: 8),

            footer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            footer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            footer.widthAnchor.constraint(equalToConstant: 80),
            footer.heightAnchor.constraint(equalToConstant: 8),
        ])

        return card
    }
}
