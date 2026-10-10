//
//  Write.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/forums/Write.svelte, with src/lib/components/ui/markdown/markdown.svelte and the
//  Dialog of src/lib/components/ui/dialog/
//

import UIKit
import WebKit

/// `<Markdown class='form-control w-full shrink-0 min-h-56 rounded-none flex-grow'>` of `ui/markdown`: OverType,
/// the library the interface uses, in a web view that has the same options and the same theme (`Resources/Markdown`).
/// Its toolbar, shortcuts, syntax colouring and list handling are the library's own. The text comes out through
/// `onChange` as it is typed.
final class MarkdownEditorView: UIView, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var onChange: ((String) -> Void)?
    private(set) var value: String
    private let placeholder: String
    private let webView: WKWebView

    init(value: String, placeholder: String) {
        self.value = value
        self.placeholder = placeholder
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        backgroundColor = .clear
        // `shadow-sm` of the box: `0 1px 2px 0 rgb(0 0 0 / 0.05)`
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // the text area scrolls inside the page; the page itself does not
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        webView.configuration.userContentController.add(MarkdownWeakMessageHandler(self), name: "change")

        if let url = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Markdown") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("[MarkdownEditor] Missing bundled editor page")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "change")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }

    private static func literal(_ text: String) -> String {
        (try? JSONEncoder().encode(text)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    /// What the editor holds now, which is what `bind:value` has at the moment of a click.
    func fetchValue(_ completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("window.HayaseEditor ? window.HayaseEditor.value() : null") { [weak self] result, _ in
            if let text = result as? String { self?.value = text }
            completion(self?.value ?? "")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "change", let text = message.body as? String else { return }
        value = text
        onChange?(text)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.HayaseEditor.mount(\(Self.literal(value)), \(Self.literal(placeholder)))")
    }

    private func open(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else { return }
        UIApplication.shared.open(url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // the page of the editor is the only thing that loads here: a link goes to the browser
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { open(url) }
        return nil
    }
}

private final class MarkdownWeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// `Write.svelte`'s `<Dialog.Content>`: `bottom-0 border-b-0 p-0 !pb-4 flex flex-col gap-4 h-[90%] sm:h-1/2 max-w-full
/// border-0 border-t !rounded-none`: a panel as wide as the window against its bottom edge, with the editor
/// (`flex-grow`, at least `min-h-56`), the Close and Send buttons (`px-4`, at the right, `gap-2`) and the dialog's
/// close button at `right-4 top-4`. Its `!translate-y-[unset]` makes the whole `transform` of the rule important, so
/// the fly and the scale of `flyAndScale` never play: the panel only fades, over 200ms, and the overlay over 150.
final class ThreadWriteViewController: UIViewController, KeyboardEventListener {
    private static let placeholder = "Write a comment on AniList \n\nDO NOT ASK FOR HELP HERE!\n\nAsking questions such as \"why isnt X playing\" or \"why cant i find any torrents\" !__WILL GET YOU BANNED__!\n\nTHIS IS A 3RD PARTY FORUM!"
    /// Called with the text when Send is pressed.
    var onSend: ((String) -> Void)?
    /// Called with the text as it is typed: `Write.svelte` keeps it in `value`, so the same button has it again.
    var onChange: ((String) -> Void)?

    private let editor: MarkdownEditorView
    private let backdrop = UIControl()
    private let stripedBackdrop = HayaseStripedBackdropView()
    private let panel = UIView()
    private let topBorder = UIView()
    private let buttonRow = UIStackView()
    private var closing = false
    private var panelAnimator: UIViewPropertyAnimator?

    /// `flyAndScale`'s `cubicOut`
    private static let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 1.0 / 3, y: 1),
                                                        controlPoint2: CGPoint(x: 2.0 / 3, y: 1))

    init(value: String = "") {
        editor = MarkdownEditorView(value: value, placeholder: Self.placeholder)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        editor.onChange = { [weak self] text in self?.onChange?(text) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // `Dialog.Overlay`: `custom-bg`, which a click on (not on the panel) closes
        stripedBackdrop.isUserInteractionEnabled = false
        backdrop.addSubview(stripedBackdrop)
        backdrop.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(backdrop)

        panel.backgroundColor = UIColor.HayaseTheme.popover
        // `shadow-lg`: `0 10px 15px -3px rgb(0 0 0 / 0.1)`
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.1
        panel.layer.shadowOffset = CGSize(width: 0, height: 10)
        panel.layer.shadowRadius = 7.5
        panel.accessibilityViewIsModal = true
        view.addSubview(panel)

        topBorder.backgroundColor = UIColor.HayaseTheme.border   // `border-t`
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        editor.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = makeTextButton("Close", primary: false)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        let sendButton = makeTextButton("Send", primary: true)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .fill
        buttonRow.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)   // `px-4`
        buttonRow.isLayoutMarginsRelativeArrangement = true
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(UIView())   // `justify-end`
        buttonRow.addArrangedSubview(closeButton)
        buttonRow.addArrangedSubview(sendButton)

        // `Dialog.Close`: Cross2 `size-4` at `absolute right-4 top-4`, from the inside of the border
        let crossButton = HayaseCloseButton()
        crossButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        crossButton.translatesAutoresizingMaskIntoConstraints = false

        [topBorder, editor, buttonRow, crossButton].forEach { panel.addSubview($0) }
        let minimumEditorHeight = editor.heightAnchor.constraint(greaterThanOrEqualToConstant: 224)   // `min-h-56`
        minimumEditorHeight.priority = UILayoutPriority(750)
        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: panel.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            editor.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -16),   // `gap-4`
            minimumEditorHeight,

            buttonRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16),   // `!pb-4`
            buttonRow.heightAnchor.constraint(equalToConstant: 36),

            crossButton.topAnchor.constraint(equalTo: topBorder.bottomAnchor, constant: 16),
            crossButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            crossButton.widthAnchor.constraint(equalToConstant: 16),
            crossButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    /// `<Button variant='secondary'>` (Close) and `<Button>` (Send), size default: h-9 px-4 py-2 text-sm font-medium
    private func makeTextButton(_ title: String, primary: Bool) -> SelectButton {
        let button = SelectButton(frame: .zero)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)
        if primary { button.applyPrimaryVariant() } else { button.applySecondaryVariant() }
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return button
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        stripedBackdrop.frame = backdrop.bounds
        // The dialog is `bottom-0` of the window, `h-[90%]`, or `sm:h-1/2` from 640 on. A keyboard makes the window
        // what is above it, so the panel stays where it is seen.
        let viewport = view.window?.bounds.width ?? view.bounds.width
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let keyboardTop = view.keyboardLayoutGuide.layoutFrame.minY
        let windowBottom = keyboardTop < safe.maxY - 1 ? keyboardTop : view.bounds.maxY
        let fraction: CGFloat = viewport >= 640 ? 0.5 : 0.9
        // 1 (border) + `min-h-56` + `gap-4` + 36 + `!pb-4`
        let height = min(windowBottom, max(1 + 224 + 16 + 36 + 16, windowBottom * fraction))
        panel.frame = CGRect(x: 0, y: windowBottom - height, width: view.bounds.width, height: height)
        panel.layer.shadowPath = UIBezierPath(rect: panel.bounds.insetBy(dx: 3, dy: 3)).cgPath   // `-3px` of spread
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        panel.alpha = 0
        backdrop.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        // `Dialog.Overlay`: `transition:fade={{ duration: 150 }}`, which is linear
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveLinear) { self.backdrop.alpha = 1 }
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: Self.timing)
        animator.addAnimations { self.panel.alpha = 1 }
        panelAnimator = animator
        animator.startAnimation()
    }

    /// Send: the click of `Dialog.Close` runs `comment`, which reads the text as it is, and closes the dialog.
    @objc private func sendTapped() {
        guard !closing else { return }
        editor.fetchValue { [weak self] text in
            guard let self, !self.closing else { return }
            self.onSend?(text)
            self.close()
        }
    }

    @objc private func close() {
        guard !closing else { return }
        closing = true
        view.endEditing(true)
        panelAnimator?.stopAnimation(true)
        guard !UIAccessibility.isReduceMotionEnabled else {
            dismiss(animated: false)
            return
        }
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveLinear) { self.backdrop.alpha = 0 }
        let animator = UIViewPropertyAnimator(duration: 0.2, timingParameters: Self.timing)
        animator.addAnimations { self.panel.alpha = 0 }
        animator.addCompletion { [weak self] _ in self?.dismiss(animated: false) }
        panelAnimator = animator
        animator.startAnimation()
    }

    override func accessibilityPerformEscape() -> Bool { close(); return true }

    override var keyCommands: [UIKeyCommand]? {
        [.keydown(KeyboardEvent.Key.escape)]
    }

    /// `useEscapeKeydown`: the dialog that is the closest to the key closes, and the key is its alone
    func keyDown(_ event: KeyboardEvent) {
        guard event.key == KeyboardEvent.Key.escape else { return }
        close()
        event.preventDefault()
        event.stopPropagation()
    }
}
