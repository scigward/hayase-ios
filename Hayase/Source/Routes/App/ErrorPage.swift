//
//  ErrorPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/+error.svelte (and src/routes/+error.svelte, which is the same page with the
//  desktop menubar on top): the page SvelteKit shows in place of a route whose load failed. The anime page
//  is the route that can fail, with `error(500, err)` in its `+layout.ts`.
//

import UIKit

final class ErrorPageViewController: UIViewController {
    private let status: Int
    private let message: String
    private let statusLabel = UILabel()
    private let messageLabel = UILabel()
    private let separator = UIView()
    private let imageView = UIImageView()

    /// `src='/confused.webp'`
    private let image: UIImage? = {
        guard let url = Bundle.main.url(forResource: "confused", withExtension: "webp") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    private var viewportWidth: CGFloat {
        view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
    }

    init(status: Int, message: String?) {
        self.status = status
        self.message = message ?? "Error"   // `$page.error?.message ?? 'Error'`
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background

        // text-6xl, font-light, text-foreground
        statusLabel.attributedText = CSSText.string("\(status)", font: .nunito(ofSize: 60, weight: .light),
                                                    color: UIColor.HayaseTheme.foreground, lineHeight: 60)
        // text-lg text-wrap max-w-full
        messageLabel.numberOfLines = 0
        messageLabel.attributedText = CSSText.string(message, font: .nunito(ofSize: 18, weight: .light),
                                                     color: UIColor.HayaseTheme.foreground, lineHeight: 28,
                                                     lineBreak: .byWordWrapping)
        // <Separator>: bg-border
        separator.backgroundColor = UIColor.HayaseTheme.border

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityLabel = "huh"
        imageView.isAccessibilityElement = true

        [statusLabel, messageLabel, separator, imageView].forEach { view.addSubview($0) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let wide = viewportWidth >= 640   // `sm`

        // The text block: a column of `w-96` below `sm`, a row of `w-[38rem]` from it.
        let block: CGSize
        let statusSize = statusLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 60))
        let statusWidth = ceil(statusSize.width)
        var statusFrame = CGRect.zero
        var separatorFrame = CGRect.zero
        var messageFrame = CGRect.zero
        if wide {
            let container: CGFloat = min(608, bounds.width)
            let available = max(0, container - statusWidth - 49)   // `mx-6` on both sides of a 1pt rule
            let natural = ceil(messageLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width)
            let messageWidth = min(natural, available)
            let messageHeight = ceil(messageLabel.sizeThatFits(CGSize(width: messageWidth, height: .greatestFiniteMagnitude)).height)
            let height = max(60, 80, messageHeight)   // `h-20` rule
            let rowWidth = statusWidth + 49 + messageWidth
            let x = (bounds.width - rowWidth) / 2
            statusFrame = CGRect(x: x, y: (height - 60) / 2, width: statusWidth, height: 60)
            separatorFrame = CGRect(x: x + statusWidth + 24, y: (height - 80) / 2, width: 1, height: 80)
            messageFrame = CGRect(x: x + statusWidth + 49, y: (height - messageHeight) / 2, width: messageWidth, height: messageHeight)
            block = CGSize(width: rowWidth, height: height)
        } else {
            let width = min(384, bounds.width)   // w-96 max-w-full
            let messageHeight = ceil(messageLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            let x = (bounds.width - width) / 2
            statusFrame = CGRect(x: (bounds.width - statusWidth) / 2, y: 0, width: statusWidth, height: 60)
            separatorFrame = CGRect(x: (bounds.width - 160) / 2, y: 60 + 24, width: 160, height: 1)   // my-6 w-40
            messageFrame = CGRect(x: x, y: 60 + 24 + 1 + 24, width: width, height: messageHeight)
            block = CGSize(width: width, height: messageFrame.maxY)
        }

        // <Load class='w-96 max-w-full'>: as wide as it can be up to 24rem, as tall as the picture is
        var imageSize = CGSize.zero
        if let image, image.size.width > 0 {
            let width = min(384, bounds.width)
            imageSize = CGSize(width: width, height: width * image.size.height / image.size.width)
        }

        // flex-col items-center justify-center gap-9
        let total = block.height + 36 + imageSize.height
        let top = max(0, (bounds.height - total) / 2)
        statusLabel.frame = statusFrame.offsetBy(dx: 0, dy: top)
        separator.frame = separatorFrame.offsetBy(dx: 0, dy: top)
        messageLabel.frame = messageFrame.offsetBy(dx: 0, dy: top)
        imageView.frame = CGRect(x: (bounds.width - imageSize.width) / 2, y: top + block.height + 36,
                                 width: imageSize.width, height: imageSize.height)
    }
}
