//
//  Messages.swift
//  Hayase
//
//  Mirrors: interface components/ui/chat Messages.svelte, which global chat and Watch Together
//  share, as they share this.
//
//  Web layout per message group:
//    <div class='flex flex-row mt-3' [flex-row-reverse if outgoing]>
//      <ChatProfile />                                         ← avatar at the top of the group
//      <div class='flex flex-col px-2 items-start [items-end]'>
//        <div class='pb-1 flex flex-row items-center px-1'>
//          <div class='font-bold text-sm'>{name}</div>
//          <div class='text-muted-foreground pl-2 text-[10px]'>{time}</div>
//        </div>
//        {#each _messages as message}
//          <div class='bg-muted py-2 px-3 rounded-t-xl rounded-r-xl mb-1 select-all text-xs'>{message}</div>
//        {/each}
//      </div>
//    </div>
//

import UIKit

/// What a message row shows, whichever chat it came from.
struct ChatMessageContent {
    let userID: String
    let name: String
    let avatarURL: String
    let isGuest: Bool
    let text: String
    let date: Date
}

extension IRCChatMessage {
    var content: ChatMessageContent {
        ChatMessageContent(userID: user.id, name: user.name, avatarURL: user.avatarURL,
                           isGuest: user.isGuest, text: message, date: date)
    }
}

extension W2GChatMessage {
    var content: ChatMessageContent {
        ChatMessageContent(userID: user.id, name: user.name, avatarURL: user.resolvedAvatarURL,
                           isGuest: user.guest, text: message, date: date)
    }
}

extension UITableView {
    /// A newest-first message list shown upside down, so that row 0 sits at the bottom. A
    /// `flex-col-reverse` scroller keeps the newest message in view while you are at the bottom and
    /// leaves what you are reading where it is when you are not.
    func reloadFlippedMessages(_ update: () -> Void) {
        let atBottom = contentOffset.y + adjustedContentInset.top <= 1
        let previousHeight = contentSize.height
        update()
        reloadData()
        if atBottom {
            scrollToNewestMessage()
        } else {
            layoutIfNeeded()
            contentOffset.y += contentSize.height - previousHeight
        }
    }

    func scrollToNewestMessage() {
        guard numberOfSections > 0, numberOfRows(inSection: 0) > 0 else { return }
        scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }
}

final class ChatMessageCell: UITableViewCell {
    static let reuseID = "ChatMessageCell"
    private static let avatarSize: CGFloat = 32 // size-8, Profile.svelte's default

    private let profileStack = FollowerAvatarStackView()
    private let headerRow = UIView()
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let bubbleBackground = ChatBubbleView()

    private var incomingConstraints: [NSLayoutConstraint] = []
    private var outgoingConstraints: [NSLayoutConstraint] = []
    private var headerVisibleConstraint: NSLayoutConstraint!
    private var headerHiddenConstraint: NSLayoutConstraint!
    private var headerTopConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        let cv = contentView
        let avatarSize = Self.avatarSize

        profileStack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(profileStack)

        headerRow.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(headerRow)

        nameLabel.font = .nunito(ofSize: 14, weight: .bold)
        nameLabel.textColor = UIColor.HayaseTheme.foreground
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(nameLabel)

        timeLabel.font = .nunito(ofSize: 10)
        timeLabel.textColor = UIColor.HayaseTheme.mutedForeground
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(timeLabel)

        bubbleBackground.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(bubbleBackground)

        NSLayoutConstraint.activate([
            profileStack.widthAnchor.constraint(equalToConstant: avatarSize),
            profileStack.heightAnchor.constraint(equalToConstant: avatarSize),
            profileStack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12), // mt-3, level with the header

            nameLabel.topAnchor.constraint(equalTo: headerRow.topAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 4),
            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            headerRow.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 4),
            headerRow.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -4),

            // This -4 bottom inset (shared by every row, header or
            // continuation) is what stands in for `mb-1` (4px), applied to
            // every message bubble on web regardless of position in its
            // group. headerHiddenConstraint below adds no further offset,
            // so two bubbles in the same group end up exactly 4pt apart,
            // not 4+4.
            bubbleBackground.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -4),
        ])

        headerTopConstraint = headerRow.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12) // mt-3
        headerVisibleConstraint = bubbleBackground.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 4) // pb-1
        headerHiddenConstraint = bubbleBackground.topAnchor.constraint(equalTo: cv.topAnchor, constant: 0)

        incomingConstraints = [
            profileStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 4),
            headerRow.leadingAnchor.constraint(equalTo: profileStack.trailingAnchor, constant: 8),
            bubbleBackground.leadingAnchor.constraint(equalTo: profileStack.trailingAnchor, constant: 8),
            // max-w-[calc(100%-100px)] of the column, which is the cell less the avatar and its px-2
            bubbleBackground.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -104),
        ]

        outgoingConstraints = [
            profileStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
            headerRow.trailingAnchor.constraint(equalTo: profileStack.leadingAnchor, constant: -8),
            bubbleBackground.trailingAnchor.constraint(equalTo: profileStack.leadingAnchor, constant: -8),
            bubbleBackground.leadingAnchor.constraint(greaterThanOrEqualTo: cv.leadingAnchor, constant: 104),
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        NSLayoutConstraint.deactivate(incomingConstraints)
        NSLayoutConstraint.deactivate(outgoingConstraints)
        headerVisibleConstraint.isActive = false
        headerHiddenConstraint.isActive = false
        headerTopConstraint.isActive = false
        profileStack.reset()
    }

    /// The header and the avatar go on the first message of a group; `isOutgoing` is that first
    /// message's, as the group takes its side from it.
    func configure(with message: ChatMessageContent, showHeader: Bool, isOutgoing: Bool) {
        nameLabel.text = message.name
        timeLabel.text = ChatTime.string(for: message.date)

        NSLayoutConstraint.activate(isOutgoing ? outgoingConstraints : incomingConstraints)

        headerRow.isHidden = !showHeader
        headerTopConstraint.isActive = showHeader
        headerVisibleConstraint.isActive = showHeader
        headerHiddenConstraint.isActive = !showHeader

        if showHeader {
            let summary = AniListUserSummary(id: Int(message.userID) ?? 0,
                                             name: message.name,
                                             avatarURL: message.avatarURL)
            let isGuest = message.isGuest
            profileStack.configure(users: [summary],
                                    avatarSize: Self.avatarSize,
                                    ringWidth: 4,
                                    ringColor: UIColor.HayaseTheme.background) { id, completion in
                guard !isGuest else {
                    completion(nil)
                    return
                }
                AniListClient.shared.fetchUserProfileResult(id: id) { result in
                    completion(try? result.get())
                }
            }
        } else {
            profileStack.reset()
        }

        // `bg-muted` (incoming) / fixed `theme` accent (`!bg-theme`, outgoing).
        // Quirk, not a style choice: Messages.svelte always includes the
        // static `rounded-t-xl rounded-r-xl`, then adds `rounded-l-xl` via
        // `class:` for outgoing messages *without* removing the static
        // `rounded-r-xl` (Svelte's `class:` doesn't dedupe with a static
        // class list). So outgoing bubbles end up with rounded-t + rounded-r
        // + rounded-l all at once — every corner rounded, no "tail" — while
        // incoming keeps the static rounded-t + rounded-r only (one sharp
        // corner, bottom-left, next to the avatar).
        bubbleBackground.configure(
            text: message.text,
            background: isOutgoing ? UIColor.HayaseTheme.theme : UIColor.HayaseTheme.muted,
            corners: isOutgoing
                ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner])
    }
}

extension Array {
    /// The messages of a newest-first list, grouped as `Messages.svelte`'s `groupMessages` does: a
    /// row shows the group's header and avatar when the one visually above it is from another user,
    /// and takes its side from the first (oldest) message of its group.
    func groupInfo<ID: Equatable>(at row: Int, id: (Element) -> ID) -> (showHeader: Bool, firstIndex: Int) {
        let user = id(self[row])
        var first = row
        while first + 1 < count, id(self[first + 1]) == user { first += 1 }
        return (first == row, first)
    }
}

// MARK: - ChatBubbleView

//  Mirrors: interface components/ui/chat Messages.svelte and MessageToast.svelte, whose message
//  bubble is `bg-muted py-2 px-3 rounded-t-xl mb-1 select-all text-xs whitespace-pre-wrap`.

/// A chat message's bubble. Its text is selected as a whole when it is tapped (`select-all`).
final class ChatBubbleView: UIView {
    private let textView = ChatBubbleTextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12   // rounded-xl
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),               // py-2
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),      // px-3
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    private static func attributes(font: UIFont, cssLineBox: Bool) -> [NSAttributedString.Key: Any] {
        if cssLineBox {
            return CSSText.attributes(font: font, color: UIColor.HayaseTheme.foreground,
                                      lineHeight: 16, lineBreak: .byWordWrapping)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 16   // text-xs
        paragraph.maximumLineHeight = 16
        return [
            .font: font,
            .foregroundColor: UIColor.HayaseTheme.foreground,
            .paragraphStyle: paragraph,
        ]
    }

    func configure(text: String, background: UIColor, corners: CACornerMask,
                   font: UIFont = .nunito(ofSize: 12), cssLineBox: Bool = false) {
        textView.attributedText = NSAttributedString(string: text, attributes: Self.attributes(font: font, cssLineBox: cssLineBox))
        backgroundColor = background
        layer.maskedCorners = corners
    }

    /// The size a bubble takes for `text` when it can be at most `maxWidth` wide, for callers that
    /// lay out by hand.
    static func size(for text: String, maxWidth: CGFloat,
                     font: UIFont = .nunito(ofSize: 12), cssLineBox: Bool = false) -> CGSize {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(0, maxWidth - 24), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(font: font, cssLineBox: cssLineBox), context: nil)
        return CGSize(width: ceil(bounds.width) + 24, height: ceil(bounds.height) + 16)
    }
}

private final class ChatBubbleTextView: UITextView {
    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        addInteraction(editMenu)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectEverything)))
    }

    private lazy var editMenu = UIEditMenuInteraction(delegate: nil)

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func selectEverything() {
        becomeFirstResponder()
        selectedRange = NSRange(location: 0, length: ((text ?? "") as NSString).length)
        editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil,
                                                               sourcePoint: CGPoint(x: bounds.midX, y: bounds.minY)))
    }
}
