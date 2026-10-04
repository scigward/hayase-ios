//
//  LicensePage.swift
//  Hayase
//
//  Mirrors: src/routes/app/license/+page.svelte and +page.ts (which loads `/LICENSE.txt`, the licence of the
//  interface followed by those of what it bundles). Here the text is `LICENSE.txt` in the app bundle.
//

import UIKit

final class LicensePageViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textView = UITextView()

    /// `data.licenseText`
    private let licenseText: String = {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    private var viewportWidth: CGFloat {
        view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        // <h2 class='text-2xl font-bold'>
        titleLabel.attributedText = CSSText.string("License Information",
                                                   font: .nunito(ofSize: 24, weight: .bold),
                                                   color: UIColor.HayaseTheme.foreground, lineHeight: 32)
        // <p class='text-muted-foreground'>
        subtitleLabel.numberOfLines = 0
        subtitleLabel.attributedText = CSSText.string("License information for the apps interface and its dependencies.",
                                                      font: .nunito(ofSize: 16, weight: .regular),
                                                      color: UIColor.HayaseTheme.mutedForeground, lineHeight: 24,
                                                      lineBreak: .byWordWrapping)

        // <pre class='whitespace-pre-wrap text-sm select-text break-all'>
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        let monospace = UIFont(name: "Courier", size: 14) ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.attributedText = CSSText.string(licenseText, font: monospace,
                                                 color: UIColor.HayaseTheme.foreground, lineHeight: 20,
                                                 lineBreak: .byCharWrapping)
        textView.linkTextAttributes = [:]

        [titleLabel, subtitleLabel, textView].forEach { scrollView.addSubview($0) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds

        // p-3 md:p-10 md:pb-0 pb-0
        let padding: CGFloat = viewportWidth >= 768 ? 40 : 12
        let width = max(0, view.bounds.width - padding * 2)
        var y = padding

        // space-y-0.5 w-full
        titleLabel.frame = CGRect(x: padding, y: y, width: width, height: 32)
        y += 32 + 2
        let subtitleHeight = ceil(subtitleLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        subtitleLabel.frame = CGRect(x: padding, y: y, width: width, height: subtitleHeight)
        y += subtitleHeight + 24   // gap-6

        let textHeight = ceil(textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        textView.frame = CGRect(x: padding, y: y, width: width, height: textHeight)
        y += textHeight

        scrollView.contentSize = CGSize(width: view.bounds.width, height: y)
    }
}
