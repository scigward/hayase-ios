//
//  ExtensionInstallPrompt.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/extensions/ExtensionInstallPrompt.svelte, which routes/+layout.svelte shows
//  while `extensionInstalURL` is set: by `native.navigate('extensions')` and by the route
//  `routes/app/extensions/install/[...url]`. A dialog that fetches the manifest of a link, validates it, lists
//  what is new and what is installed already, and installs the new ones.
//
//  The dialog scrolls as a whole, where the interface keeps its header and footer in place and scrolls only
//  the list between them.
//

import UIKit

// MARK: - ExtensionInstallPrompt

enum ExtensionInstallPrompt {
    /// `extensionInstalURL.set(sanitizeExtensionUrl(url))`: opens the dialog for a link.
    @MainActor
    static func show(url: String) {
        let address = ExtensionService.sanitizeExtensionURL(url)
        guard !address.isEmpty, let presenter = topPresenter() else { return }
        if let open = presenter as? ExtensionInstallPromptViewController {
            // one dialog at a time: the link replaces the one on show
            open.dismiss(animated: false) { Self.show(url: url) }
            return
        }
        presenter.present(ExtensionInstallPromptViewController(url: address), animated: false)
    }

    @MainActor
    private static func topPresenter() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}

/// The preview source dialog is `!w-auto max-w-[95%]`, unlike the installed source viewer's 80vw/70vh.
private final class ExtensionSourcePreviewDialog: SettingsDialogViewController {
    private let titleMeasure: UILabel
    private var naturalWidth: CGFloat
    private var naturalBodyHeight: CGFloat = 80
    private var bodyHeight: NSLayoutConstraint?

    override init(title: String, maximumWidth: CGFloat = CGFloat.greatestFiniteMagnitude,
                  contentInset: CGFloat = 24, heightFraction: CGFloat = 0.95) {
        titleMeasure = SettingsTypography.label(title, size: 18, lineHeight: 18, weight: .bold)
        naturalWidth = titleMeasure.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)).width
        super.init(title: title, maximumWidth: maximumWidth, contentInset: contentInset, heightFraction: heightFraction)
    }

    required init?(coder: NSCoder) { nil }

    func configureSourceView(_ text: UITextView, source: String, font: UIFont, lineHeight: CGFloat, padding: CGFloat) {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        let sourceWidth = lines.reduce(CGFloat.zero) { max($0, ($1 as NSString).size(withAttributes: [.font: font]).width) }
        naturalWidth = max(naturalWidth, sourceWidth + padding * 2)
        naturalBodyHeight = max(lineHeight, CGFloat(lines.count) * lineHeight) + padding * 2
        // `w-max whitespace-pre-wrap`: long lines scroll horizontally, rather than wrapping to panel width.
        text.textContainer.widthTracksTextView = false
        text.textContainer.size = CGSize(width: max(1, ceil(sourceWidth) + 1), height: CGFloat.greatestFiniteMagnitude)
        bodyHeight = text.heightAnchor.constraint(equalToConstant: naturalBodyHeight)
        bodyHeight?.isActive = true
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        preferredPanelWidth = min(view.bounds.width * 0.95, ceil(naturalWidth) + 50) // p-6 + border
        let titleHeight = titleMeasure.sizeThatFits(CGSize(width: max(1, (preferredPanelWidth ?? 50) - 50),
                                                          height: CGFloat.greatestFiniteMagnitude)).height
        // Fixed title, Close (36), two gap-4 spaces, and p-6 + border leave the code's scroll area.
        bodyHeight?.constant = min(naturalBodyHeight, max(1, view.bounds.height * 0.95 - titleHeight - 118))
        super.viewDidLayoutSubviews()
    }
}

/// `<div class='py-8'><div class='animate-spin size-4 border-2 ... border-t-transparent' /></div>`.
private final class ExtensionSourcePreviewSpinner: UIView {
    private let ring = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        heightAnchor.constraint(equalToConstant: 80).isActive = true
        ring.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        ring.path = UIBezierPath(arcCenter: CGPoint(x: 8, y: 8), radius: 7,
            startAngle: -.pi / 4, endAngle: 5 * .pi / 4, clockwise: true).cgPath
        ring.fillColor = nil
        ring.strokeColor = UIColor.HayaseTheme.mutedForeground.cgColor
        ring.lineWidth = 2
        layer.addSublayer(ring)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        ring.removeAnimation(forKey: "spin")
        guard window != nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 1
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        ring.add(spin, forKey: "spin")
    }
}

// MARK: - ExtensionInstallPromptViewController

final class ExtensionInstallPromptViewController: SettingsDialogViewController {
    private let url: String
    private var configs: [ExtensionConfig] = []
    private var error: String?
    private var importing = false
    private var fetchTask: Task<Void, Never>?
    private let body = UIStackView()
    private let footer = UIStackView()

    private static var viewportWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController?.view.bounds.width ?? UIScreen.main.bounds.width
    }

    init(url: String) {
        self.url = url
        // `max-w-3xl bg-background p-4 md:p-6`, up to `max-h-[95%]`
        super.init(title: "", maximumWidth: 768, contentInset: Self.viewportWidth >= 768 ? 24 : 16, heightFraction: 0.95)
        panelColor = UIColor.HayaseTheme.background
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        fetchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // <Dialog.Header>: `space-y-1.5`
        let title = SettingsTypography.label("Install Extensions", size: 18, lineHeight: 18, weight: .semibold)
        let description = UILabel()
        description.numberOfLines = 1
        description.attributedText = CSSText.string(url, font: .nunito(ofSize: 14, weight: .regular),
                                                    color: UIColor.HayaseTheme.mutedForeground, lineHeight: 20)   // `truncate`
        let header = SettingsDialogHeader(title: title, description: description)
        content.addArrangedSubview(header)

        body.axis = .vertical
        body.spacing = 12   // gap-3
        content.addArrangedSubview(body)

        footer.spacing = 8   // gap-2
        content.addArrangedSubview(footer)

        render()
        fetchManifest()
    }

    // MARK: - fetchManifest

    private func fetchManifest() {
        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let all = await ExtensionService.shared.manifest(at: self.url) else {
                guard !Task.isCancelled else { return }
                self.error = "Could not fetch extension manifest from the provided URL."
                self.render()
                return
            }
            guard !Task.isCancelled else { return }
            let invalid = all.filter { !ExtensionService.shared.isValid($0) }
            if !invalid.isEmpty {
                self.error = "Invalid extension config: \(invalid.map { $0.name.isEmpty ? $0.id : $0.name }.joined(separator: ", "))"
            } else {
                self.configs = all
            }
            self.render()
        }
    }

    // MARK: - install

    private func install() {
        guard !importing else { return }
        importing = true
        render()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await ExtensionService.shared.importExtension(from: self.url)
                AppErrorToast.success("Extensions installed successfully!")
                self.close()
            } catch {
                // `toast.error(error.cause, { description: error.message, duration: 15_000 })`
                AppErrorToast.show(error.localizedDescription,
                                   title: (error as? ExtensionError)?.toastTitle ?? "Invalid extension URI")
                self.importing = false
                self.render()
            }
        }
    }

    // MARK: - Rendering

    /// `$: newConfigs`, `$: existingConfigs`
    private func render() {
        guard isViewLoaded else { return }
        let installed = Set(ExtensionService.shared.configs.keys)
        let newConfigs = configs.filter { !installed.contains($0.id) }
        let existingConfigs = configs.filter { installed.contains($0.id) }

        body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
        if let error {
            // `py-8 gap-4 text-center`
            let failed = SettingsTypography.label("Failed to load", size: 18, lineHeight: 28, weight: .bold,
                                                  color: UIColor.HayaseTheme.destructive)
            let message = SettingsTypography.label(error, size: 14, lineHeight: 20, color: UIColor.HayaseTheme.mutedForeground)
            let address = SettingsTypography.label(url, size: 12, lineHeight: 16, color: UIColor.HayaseTheme.mutedForeground)
            [failed, message, address].forEach { $0.textAlignment = .center }
            let column = UIStackView(arrangedSubviews: [failed, message, address])
            column.axis = .vertical
            column.spacing = 16
            column.isLayoutMarginsRelativeArrangement = true
            column.layoutMargins = UIEdgeInsets(top: 32, left: 0, bottom: 32, right: 0)
            body.addArrangedSubview(column)
        } else {
            for config in newConfigs {
                let card = SettingsExtensionCardView(config: config, preview: true)
                card.onSource = { [weak self] in self?.showSource(config) }
                body.addArrangedSubview(card)
            }
            if !existingConfigs.isEmpty {
                // `bg-accent border border-border px-4 py-3 rounded-md`
                let title = SettingsTypography.label("Already Installed", size: 14, lineHeight: 20, weight: .bold,
                                                     color: UIColor.HayaseTheme.mutedForeground)
                let names = SettingsTypography.label("\(existingConfigs.map(\.name).joined(separator: ", ")) already exist and will be skipped.",
                                                     size: 12, lineHeight: 16, color: UIColor.HayaseTheme.mutedForeground)
                let column = UIStackView(arrangedSubviews: [title, names])
                column.axis = .vertical
                column.spacing = 4   // mt-1
                column.isLayoutMarginsRelativeArrangement = true
                column.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
                column.backgroundColor = UIColor.HayaseTheme.accent
                column.layer.borderWidth = 1
                column.layer.borderColor = UIColor.HayaseTheme.border.cgColor
                column.layer.cornerRadius = 6
                body.addArrangedSubview(column)
            }
        }

        // <Dialog.Footer class='gap-2'>: `flex-col-reverse sm:flex-row sm:justify-end`
        footer.arrangedSubviews.forEach { footer.removeArrangedSubview($0); $0.removeFromSuperview() }
        let wide = Self.viewportWidth >= 640
        footer.axis = wide ? .horizontal : .vertical
        footer.alignment = .fill
        var buttons: [UIButton] = []
        if error != nil || (newConfigs.isEmpty && !existingConfigs.isEmpty) {
            buttons = [secondaryButton("Close") { [weak self] in self?.close() }]
        } else {
            let cancel = secondaryButton("Cancel") { [weak self] in self?.close() }
            cancel.isEnabled = !importing
            cancel.alpha = cancel.isEnabled ? 1 : 0.5
            let installButton = SettingsTypography.button(importing ? "Installing..." : "Install (\(newConfigs.count))")
            installButton.isEnabled = !importing && !newConfigs.isEmpty
            installButton.alpha = installButton.isEnabled ? 1 : 0.5
            installButton.addAction(UIAction { [weak self] _ in self?.install() }, for: .touchUpInside)
            buttons = [cancel, installButton]
        }
        if wide {
            footer.addArrangedSubview(UIView())
            buttons.forEach { footer.addArrangedSubview($0) }
        } else {
            buttons.reversed().forEach { footer.addArrangedSubview($0) }
        }
    }

    /// `<Button variant='secondary'>`
    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = SettingsTypography.button(title, secondary: true)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Source code

    /// `{config.name} Source Code`: the code of an extension that is not installed yet.
    private func showSource(_ config: ExtensionConfig) {
        let dialog = ExtensionSourcePreviewDialog(title: "\(config.name) Source Code")
        let spinner = ExtensionSourcePreviewSpinner(frame: .zero)
        dialog.content.addArrangedSubview(spinner)
        let close = SettingsTypography.button("Close", secondary: true)
        close.addAction(UIAction { [weak dialog] _ in dialog?.close() }, for: .touchUpInside)
        dialog.content.addArrangedSubview(close)
        present(dialog, animated: false)

        Task { @MainActor [weak dialog, weak spinner] in
            let code = try? await ExtensionService.shared.sourceCode(of: config)
            guard let dialog, let spinner else { return }
            spinner.removeFromSuperview()
            let text = UITextView()
            text.isEditable = false
            text.backgroundColor = .clear
            text.textContainer.lineFragmentPadding = 0
            text.setContentHuggingPriority(.defaultLow, for: .vertical)
            text.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            if let code, !code.isEmpty {
                let font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
                text.textContainerInset = .zero
                text.attributedText = CSSText.string(code, font: font, color: UIColor.HayaseTheme.foreground,
                    lineHeight: 24, lineBreak: .byCharWrapping)
                dialog.configureSourceView(text, source: code, font: font, lineHeight: 24, padding: 0)
            } else {
                // `Failed to load source code.`
                let font = UIFont.nunito(ofSize: 14)
                text.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
                text.attributedText = CSSText.string("Failed to load source code.", font: font,
                    color: UIColor.HayaseTheme.mutedForeground, lineHeight: 20)
                dialog.configureSourceView(text, source: "Failed to load source code.", font: font, lineHeight: 20, padding: 16)
            }
            dialog.content.insertArrangedSubview(text, at: dialog.content.arrangedSubviews.count - 1)
        }
    }
}
