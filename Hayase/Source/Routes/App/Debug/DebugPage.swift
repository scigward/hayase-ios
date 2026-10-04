//
//  DebugPage.swift
//  Hayase
//
//  Mirrors: src/routes/app/debug/+page.svelte
//
//  The page that the support asks for: five cards that save what is needed to a file (the app and device, the logs, the
//  settings, the torrent and the media capabilities), the tables of the audio and video codecs that the device can
//  decode, and the latest event of each kind that the window got. Every save also copies what it saves.
//

import UIKit

final class HayaseDebugViewController: UIViewController {
    private let scrollView = UIScrollView()
    /// `flex flex-col gap-4`
    private let page = UIStackView()
    private var pageLeading: NSLayoutConstraint!
    private var pageTrailing: NSLayoutConstraint!
    private var pageTop: NSLayoutConstraint!

    private var cards: [SettingsCardView] = []
    private let headerMaxWidth = UIView()
    private var headerWidthLimit: NSLayoutConstraint!
    private let loadingView = UIView()
    private var mediaSections: [UIView] = []

    private let inputEvents = DebugInputEvents()
    private var eventCards: [String: DebugEventCard] = [:]
    private let eventsGrid = UIStackView()
    private var eventColumns = 0

    /// `const mediaPromise = Promise.all([testAudio(), testVideo()])`: it starts with the page
    private var mediaTask: Task<(audio: [String: [Int: Int]], video: [String: [String: Bool]]), Never>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background
        navigationController?.setNavigationBarHidden(true, animated: false)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        view.addSubview(scrollView)

        page.axis = .vertical
        page.spacing = 16
        page.alignment = .fill
        page.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(page)

        pageLeading = page.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor)
        pageTrailing = page.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor)
        pageTop = page.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            pageLeading, pageTrailing, pageTop,
            // `pb-0`: the page ends where its last card does
            page.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])

        page.addArrangedSubview(makeHeader())
        makeCards().forEach { page.addArrangedSubview($0) }
        makeLoadingView()
        page.addArrangedSubview(loadingView)
        makeInputEvents().forEach { page.addArrangedSubview($0) }

        mediaTask = Task.detached(priority: .utility) {
            (audio: MediaCapabilities.testAudio(), video: MediaCapabilities.testVideo())
        }
        Task { @MainActor [weak self] in
            guard let results = await self?.mediaTask?.value else { return }
            self?.showMedia(results)
        }
        updateLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        if let window = view.window { inputEvents.start(in: window) }
        inputEvents.onChange = { [weak self] in self?.refreshEvents() }
        refreshEvents()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        inputEvents.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
    }

    /// `p-3 md:p-10 md:pb-0 pb-0`, and what the page does at `md` and `lg`
    private func updateLayout() {
        let width = viewportWidth
        let padding: CGFloat = width >= 768 ? 40 : 12
        pageLeading.constant = padding
        pageTrailing.constant = -padding
        pageTop.constant = padding
        headerWidthLimit.isActive = width >= 1024   // `lg:max-w-[1440px]`
        cards.forEach { $0.updateLayout(viewportWidth: width) }
        arrangeEvents(columns: width >= 1024 ? 3 : width >= 768 ? 2 : 1)
    }

    private var viewportWidth: CGFloat {
        view.window?.rootViewController?.view.bounds.width ?? view.bounds.width
    }

    // MARK: - Keys

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        presses.forEach { inputEvents.press($0, isDown: true) }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        presses.forEach { inputEvents.press($0, isDown: false) }
        super.pressesEnded(presses, with: event)
    }

    // MARK: - Header

    private func makeHeader() -> UIView {
        // `<div class='flex justify-center'><div class='space-y-0.5 lg:max-w-[1440px] w-full'>`
        let title = SettingsTypography.label("Debug Page", size: 24, lineHeight: 32, weight: .bold)
        title.numberOfLines = 1

        let intro = LinkLabel()
        let font = UIFont.nunito(ofSize: 16)
        let text = NSMutableAttributedString(
            string: "If you're here because you're looking for support with Hayase, you're in the right place! Otherwise, you might want to check the ",
            attributes: CSSText.attributes(font: font, color: UIColor.HayaseTheme.mutedForeground, lineHeight: 24,
                                           lineBreak: .byWordWrapping))
        let start = text.length
        text.append(NSAttributedString(string: "settings", attributes: CSSText.attributes(
            font: font, color: UIColor(hex: 0x3b82f6), lineHeight: 24, lineBreak: .byWordWrapping)))
        let range = NSRange(location: start, length: text.length - start)
        text.append(NSAttributedString(string: " page.", attributes: CSSText.attributes(
            font: font, color: UIColor.HayaseTheme.mutedForeground, lineHeight: 24, lineBreak: .byWordWrapping)))
        intro.attributedText = text
        intro.links = [LinkLabel.Link(range: range) { Router.shared.navigate(.settings(.root)) }]

        let inner = UIStackView(arrangedSubviews: [title, intro])
        inner.axis = .vertical
        inner.spacing = 2
        inner.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(inner)
        let fill = inner.widthAnchor.constraint(equalTo: container.widthAnchor)
        fill.priority = .defaultHigh
        headerWidthLimit = inner.widthAnchor.constraint(lessThanOrEqualToConstant: 1440)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: container.topAnchor),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            inner.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            fill,
        ])
        return container
    }

    // MARK: - Cards

    private func makeCards() -> [UIView] {
        var views: [UIView] = []
        func card(_ title: String, _ description: String, button: String = "Save",
                  _ action: @escaping @MainActor (UIView) async throws -> Void) {
            let control = SettingsTypography.button(button)
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let self, let control else { return }
                self.run(action, from: control)
            }, for: .touchUpInside)
            let card = SettingsCardView(title: title, description: description, control: control)
            cards.append(card)
            views.append(card)
        }

        card("App and Device Info", "Save app and device debug info and capabilities, such as GPU information, GPU capabilities, version information and settings to a file.", saveDeviceInfo)
        card("Device Logs", "Save device logs to a file, which can be useful for debugging issues. If you want to share these logs with the developers, please make sure to check the contents of the logs before sharing, as they might contain sensitive information.", saveLogs)
        card("Settings", "Save current settings to a file, which can be useful for debugging issues or sharing your configuration with others.", saveSettings)
        card("Torrent Capabilities", "Save torrent capabilities of the device, which can be useful for debugging issues with torrenting. This includes information about supported protocols, encryption, and other torrent-related features.", saveTorrent)
        card("Media Capabilities", "Save media capabilities of the device, which can be useful for debugging issues with media playback. This includes information about supported codecs, DRM capabilities, and other media-related features.", saveMedia)
        return views
    }

    /// `wrapToast`: a save that fails says so
    private func run(_ action: @escaping @MainActor (UIView) async throws -> Void, from source: UIView) {
        Task { @MainActor in
            do {
                try await action(source)
            } catch {
                AppErrorToast.show(error.localizedDescription, title: "Failed to save file!", duration: 15)
            }
        }
    }

    // MARK: - What the cards save

    /// `device`
    private func saveDeviceInfo(_ source: UIView) async throws {
        var info: [String: Any] = [
            "appVersion": Native.version(),
            "version": Native.build(),
            // `Promise.allSettled([native.updateReady()])`: there is no updater, whose answer is nothing
            "hasUpdate": ["status": "fulfilled"],
            "appInfo": [
                "support": [
                    "isAndroid": false,
                    "isAndroidTV": false,
                    "isIOS": true,
                    "isIPad": UIDevice.current.userInterfaceIdiom == .pad,
                    "isMobile": true,
                    // as the preview card has it: Low Power Mode, or under 4 GiB of memory
                    "isUnderPowered": ProcessInfo.processInfo.isLowPowerModeEnabled
                        || ProcessInfo.processInfo.physicalMemory < 4 * 1_024 * 1_024 * 1_024,
                ] as [String: Any],
            ] as [String: Any],
        ]
        info.merge(Native.getDeviceInfo()) { _, device in device }
        try SaveFile.save(info, name: "hayase-device-info", presenter: self, sourceView: source)
    }

    /// `logs`
    private func saveLogs(_ source: UIView) async throws {
        try SaveFile.save(Native.getLogs(), name: "hayase-logs", ext: "ansi", presenter: self, sourceView: source)
    }

    /// `settingsFile`: the settings, with the login and the password of the NZB hidden
    private func saveSettings(_ source: UIView) async throws {
        guard var settings = try JSONSerialization.jsonObject(with: SettingsFileService.exportData()) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        settings["nzbPassword"] = "***"
        settings["nzbLogin"] = "***"
        try SaveFile.save(settings, name: "hayase-settings", presenter: self, sourceView: source)
    }

    /// `torrent`
    private func saveTorrent(_ source: UIView) async throws {
        let manager = TorrentBackendManager.shared
        let status: WebTorrentBridgeStatus = try await withCheckedThrowingContinuation { continuation in
            manager.webTorrentStatus { continuation.resume(with: $0) }
        }
        guard let hash = status.infoHash, !hash.isEmpty else {
            throw NSError(domain: "Hayase", code: 0, userInfo: [NSLocalizedDescriptionKey: "No active torrent found"])
        }
        let storage = try Native.checkAvailableSpace()
        let info: WebTorrentTorrentInfo = try await withCheckedThrowingContinuation { continuation in
            manager.webTorrentInfo(hash: hash) { continuation.resume(with: $0) }
        }
        let trackers: [String: WebTorrentTrackerInfo] = try await withCheckedThrowingContinuation { continuation in
            manager.webTorrentTrackers(hash: hash) { continuation.resume(with: $0) }
        }
        let protocolStatus: WebTorrentProtocolStatus = try await withCheckedThrowingContinuation { continuation in
            manager.webTorrentProtocolStatus(hash: hash) { continuation.resume(with: $0) }
        }

        func json<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
        }
        try SaveFile.save([
            "storage": TorrentFormat.fastPrettyBytes(UInt64(max(0, storage))),
            "info": try json(info),
            "trackers": try json(trackers),
            "protocol": try json(protocolStatus),
        ] as [String: Any], name: "hayase-torrent-capabilities", presenter: self, sourceView: source)
    }

    /// `media`
    private func saveMedia(_ source: UIView) async throws {
        guard let results = await mediaTask?.value else { return }
        let audioMatrix = results.audio.mapValues { rates in
            Dictionary(uniqueKeysWithValues: rates.map { (String($0.key), $0.value) })
        }
        try SaveFile.save([
            "video": MediaCapabilities.playableFormats(),
            "audioMatrix": audioMatrix,
            "videoMatrix": results.video,
        ] as [String: Any], name: "hayase-media-capabilities", presenter: self, sourceView: source)
    }

    // MARK: - The tables

    /// `{#await mediaPromise}` before it is done: `<div class='flex justify-center py-8'><p class='text-muted-foreground'>`
    private func makeLoadingView() {
        let label = SettingsTypography.label("Testing media capabilities...", size: 16, lineHeight: 24,
                                             color: UIColor.HayaseTheme.mutedForeground)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: loadingView.topAnchor, constant: 32),
            label.bottomAnchor.constraint(equalTo: loadingView.bottomAnchor, constant: -32),
            label.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
        ])
    }

    /// `{:then [audioMatrix, videoMatrix]}`
    private func showMedia(_ results: (audio: [String: [Int: Int]], video: [String: [String: Bool]])) {
        guard let index = page.arrangedSubviews.firstIndex(of: loadingView) else { return }
        loadingView.removeFromSuperview()

        let green = UIColor(hex: 0x22c55e)
        let amber = UIColor(hex: 0xfbbf24)
        let faint = UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.3)

        let audioRows = MediaCapabilities.audioCodecs.map { codec, name in
            DebugMatrixView.Row(name: name, cells: MediaCapabilities.sampleRates.map { rate in
                let channels = results.audio[codec]?[rate] ?? 0
                let text = channels > 0 ? "\(channels)ch" : "—"
                if channels >= 6 { return .init(text: text, color: green, medium: true) }
                if channels >= 2 { return .init(text: text, color: UIColor.HayaseTheme.foreground, medium: false) }
                if channels >= 1 { return .init(text: text, color: amber, medium: false) }
                return .init(text: text, color: faint, medium: false)
            })
        }
        let audio = makeSection(
            title: "Audio Codec Support",
            legend: [("Maximum supported channels per sample rate. ", UIColor.HayaseTheme.mutedForeground, false),
                     ("≥6ch", green, true), (" · ", UIColor.HayaseTheme.mutedForeground, false),
                     ("2–4ch", UIColor.HayaseTheme.foreground, false), (" · ", UIColor.HayaseTheme.mutedForeground, false),
                     ("unsupported", UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.4), false)],
            matrix: DebugMatrixView(headers: MediaCapabilities.sampleRates.map { "\(Int((Double($0) / 1000).rounded()))k" },
                                    rows: audioRows))

        let videoRows = MediaCapabilities.videoCodecs.map { codec, name in
            DebugMatrixView.Row(name: name, cells: MediaCapabilities.resolutions.map { resolution in
                results.video[codec]?[resolution.label] == true
                    ? .init(text: "✓", color: green, medium: true) : .init(text: "—", color: faint, medium: false)
            })
        }
        let video = makeSection(
            title: "Video Codec Support",
            legend: [("Decoding support per codec and resolution. ", UIColor.HayaseTheme.mutedForeground, false),
                     ("✓ supported", green, true), (" · ", UIColor.HayaseTheme.mutedForeground, false),
                     ("— unsupported", UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.4), false)],
            matrix: DebugMatrixView(headers: MediaCapabilities.resolutions.map { $0.label }, rows: videoRows))

        mediaSections = [audio, video]
        page.insertArrangedSubview(audio, at: index)
        page.insertArrangedSubview(video, at: index + 1)
    }

    /// `<div class='space-y-1.5'>` with an `h3`, the legend and the table
    private func makeSection(title: String, legend: [(String, UIColor, Bool)], matrix: DebugMatrixView) -> UIView {
        let heading = SettingsTypography.label(title, size: 18, lineHeight: 28, weight: .bold)
        let text = NSMutableAttributedString()
        for (part, color, medium) in legend {
            text.append(CSSText.string(part, font: .nunito(ofSize: 12, weight: medium ? .medium : .regular), color: color,
                                       lineHeight: 16, lineBreak: .byWordWrapping))
        }
        let legendLabel = UILabel()
        legendLabel.numberOfLines = 0
        legendLabel.attributedText = text
        let section = UIStackView(arrangedSubviews: [heading, legendLabel, matrix])
        section.axis = .vertical
        section.spacing = 6
        // `pb-1` of the legend
        section.setCustomSpacing(10, after: legendLabel)
        return section
    }

    // MARK: - Input Events

    private func makeInputEvents() -> [UIView] {
        // `<SettingCard title='Input Events' description='...' />`: no control
        let none = UIView()
        none.isHidden = true
        let card = SettingsCardView(title: "Input Events",
                                    description: "Latest mouse, keyboard, pointer, touch, and wheel events per constructor.",
                                    control: none)
        cards.append(card)

        eventsGrid.axis = .vertical
        eventsGrid.spacing = 12
        eventsGrid.alignment = .fill
        for source in DebugInputEvents.sources { eventCards[source] = DebugEventCard(source: source) }
        return [card, eventsGrid]
    }

    /// `grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3`
    private func arrangeEvents(columns: Int) {
        guard columns != eventColumns else { return }
        eventColumns = columns
        eventsGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let sources = DebugInputEvents.sources
        var index = 0
        while index < sources.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 12
            row.alignment = .fill
            row.distribution = .fillEqually
            for column in 0..<columns {
                if index + column < sources.count, let eventCard = eventCards[sources[index + column]] {
                    row.addArrangedSubview(eventCard)
                } else {
                    row.addArrangedSubview(UIView())   // the cells of the last row are as wide as the others
                }
            }
            eventsGrid.addArrangedSubview(row)
            index += columns
        }
    }

    private func refreshEvents() {
        for source in DebugInputEvents.sources {
            eventCards[source]?.show(inputEvents.events[source])
        }
    }
}

// MARK: - One event

/// `<div class='rounded-md border p-3 space-y-1.5' class:opacity-30={!ev}>`
private final class DebugEventCard: UIView {
    private let source: String
    private let stack = UIStackView()

    private static let colors: [String: (background: UIColor, text: UIColor)] = [
        "Mouse": (UIColor(hex: 0x22c55e, alpha: 0.1), UIColor(hex: 0x4ade80)),
        "Keyboard": (UIColor(hex: 0xf59e0b, alpha: 0.1), UIColor(hex: 0xfbbf24)),
        "Pointer": (UIColor(hex: 0xa855f7, alpha: 0.1), UIColor(hex: 0xc084fc)),
        "Wheel": (UIColor(hex: 0x06b6d4, alpha: 0.1), UIColor(hex: 0x22d3ee)),
        "Touch": (UIColor(hex: 0xec4899, alpha: 0.1), UIColor(hex: 0xf472b6)),
    ]

    init(source: String) {
        self.source = source
        super.init(frame: .zero)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.HayaseTheme.border.cgColor
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
        ])
        show(nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(_ event: DebugInputEvents.Event?) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        alpha = event == nil ? 0.3 : 1

        // `flex flex-wrap items-center gap-1.5`
        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 6
        header.alignment = .center
        let name = UILabel()
        name.attributedText = CSSText.string(source.uppercased(), font: .nunito(ofSize: 12, weight: .bold),
                                             color: UIColor.HayaseTheme.mutedForeground, lineHeight: 16, kern: 0.6)
        header.addArrangedSubview(name)
        if let event {
            let colors = Self.colors[source] ?? (UIColor(hex: 0x6b7280, alpha: 0.1), UIColor(hex: 0x9ca3af))
            header.addArrangedSubview(Self.badge(source, background: colors.background, text: colors.text))
            header.addArrangedSubview(Self.badge(event.type, background: UIColor(hex: 0x3b82f6, alpha: 0.1),
                                                 text: UIColor(hex: 0x60a5fa)))
        } else {
            let waiting = UILabel()
            waiting.attributedText = CSSText.string("awaiting event…", font: .nunito(ofSize: 10),
                                                    color: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.4),
                                                    lineHeight: 15)
            header.addArrangedSubview(waiting)
        }
        header.addArrangedSubview(UIView())
        stack.addArrangedSubview(header)

        guard let event else { return }
        // `text-xs text-muted-foreground space-y-0.5`
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 2
        rows.addArrangedSubview(Self.row("target", event.target, truncates: true))
        rows.addArrangedSubview(Self.row("time", event.time))
        if let x = event.x, let y = event.y { rows.addArrangedSubview(Self.row("position", "\(Self.number(x)), \(Self.number(y))")) }
        if let key = event.key {
            rows.addArrangedSubview(Self.row("key", key, badge: true))
            rows.addArrangedSubview(Self.row("code", event.code ?? ""))
        }
        if let button = event.button { rows.addArrangedSubview(Self.row("button", String(button))) }
        if let deltaY = event.deltaY {
            rows.addArrangedSubview(Self.row("deltaY", (deltaY > 0 ? "↓" : "↑") + " " + Self.number(abs(deltaY))))
        }
        if let touches = event.touches { rows.addArrangedSubview(Self.row("touches", String(touches))) }
        rows.addArrangedSubview(Self.row("modifiers", event.modifiers))
        stack.addArrangedSubview(rows)
    }

    /// `rounded px-1 py-0.5 text-[10px] font-bold`
    private static func badge(_ text: String, background: UIColor, text color: UIColor) -> UIView {
        let label = UILabel()
        label.attributedText = CSSText.string(text, font: .nunito(ofSize: 10, weight: .bold), color: color, lineHeight: 15)
        let view = UIView()
        view.backgroundColor = background
        view.layer.cornerRadius = 4
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
        ])
        return view
    }

    /// `<div class='flex justify-between'><span class='text-muted-foreground/50'>label</span><span>value</span></div>`
    private static func row(_ label: String, _ value: String, truncates: Bool = false, badge: Bool = false) -> UIView {
        let name = UILabel()
        name.attributedText = CSSText.string(label, font: .nunito(ofSize: 12),
                                             color: UIColor.HayaseTheme.mutedForeground.withAlphaComponent(0.5), lineHeight: 16)
        name.setContentHuggingPriority(.required, for: .horizontal)
        name.setContentCompressionResistancePriority(.required, for: .horizontal)

        let content = UILabel()
        content.textAlignment = .right
        let color = badge ? UIColor(hex: 0xfbbf24) : UIColor.HayaseTheme.mutedForeground
        content.attributedText = CSSText.string(value, font: .nunito(ofSize: 12, weight: badge ? .medium : .regular), color: color,
                                                lineHeight: 16, alignment: .right)
        content.lineBreakMode = .byTruncatingTail
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var valueView: UIView = content
        if badge {
            // `rounded px-1 bg-amber-500/10 text-amber-400 font-medium`
            let wrap = UIView()
            wrap.backgroundColor = UIColor(hex: 0xf59e0b, alpha: 0.1)
            wrap.layer.cornerRadius = 4
            content.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: wrap.topAnchor),
                content.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 4),
                content.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -4),
            ])
            valueView = wrap
        }
        if truncates {
            // `truncate max-w-[180px] text-right`
            valueView.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        }

        let row = UIStackView(arrangedSubviews: [name, UIView(), valueView])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 0
        return row
    }

    /// How JavaScript writes a number: without a ".0"
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

// MARK: - The tables

/// `<div class='rounded-md border overflow-auto'><Table.Root class='table-fixed'>`: a header row and a row for each codec, whose
/// first column is 140pt wide and the others share the rest
private final class DebugMatrixView: UIView {
    struct Cell {
        let text: String
        let color: UIColor
        let medium: Bool
    }

    struct Row {
        let name: String
        let cells: [Cell]
    }

    private static let firstColumn: CGFloat = 140
    private static let headerHeight: CGFloat = 40
    private static let rowHeight: CGFloat = 32

    private let headers: [String]
    private var rowViews: [RowView] = []
    private let headerView = UIView()
    private let headerRule = UIView()
    private var headerLabels: [UILabel] = []
    private let headerName = UILabel()

    init(headers: [String], rows: [Row]) {
        self.headers = headers
        super.init(frame: .zero)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.HayaseTheme.border.cgColor
        clipsToBounds = true

        headerName.attributedText = Self.headerText("Codec")
        headerView.addSubview(headerName)
        for header in headers {
            let label = UILabel()
            label.attributedText = Self.headerText(header, alignment: .right)
            headerView.addSubview(label)
            headerLabels.append(label)
        }
        addSubview(headerView)
        headerRule.backgroundColor = UIColor.HayaseTheme.border   // `border-b` of the header row
        addSubview(headerRule)
        for (index, row) in rows.enumerated() {
            let view = RowView(row: row, isStriped: index % 2 == 1, hasBorder: index < rows.count - 1)
            rowViews.append(view)
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// `text-[11px]/4 font-semibold uppercase tracking-wider text-muted-foreground`
    private static func headerText(_ text: String, alignment: NSTextAlignment = .natural) -> NSAttributedString {
        CSSText.string(text.uppercased(), font: .nunito(ofSize: 11, weight: .semibold),
                       color: UIColor.HayaseTheme.mutedForeground, lineHeight: 16, alignment: alignment,
                       lineBreak: .byClipping, kern: 0.55)
    }

    override var intrinsicContentSize: CGSize {
        // the border, the header and its rule, and a row and its rule for each, the last without one
        CGSize(width: UIView.noIntrinsicMetric,
               height: 2 + Self.headerHeight + 1 + CGFloat(rowViews.count) * (Self.rowHeight + 1) - 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // inside the border of the box
        let inner = bounds.insetBy(dx: 1, dy: 1)
        let width = inner.width
        let others = CGFloat(max(1, headers.count))
        let column = max(0, (width - Self.firstColumn) / others)
        headerView.frame = CGRect(x: inner.minX, y: inner.minY, width: width, height: Self.headerHeight)
        headerName.frame = CGRect(x: 8, y: 0, width: Self.firstColumn - 17, height: Self.headerHeight)
        for (index, label) in headerLabels.enumerated() {
            let last = index == headers.count - 1
            label.frame = CGRect(x: Self.firstColumn + CGFloat(index) * column + 8, y: 0,
                                 width: max(0, column - (last ? 28 : 16)), height: Self.headerHeight)
        }
        headerRule.frame = CGRect(x: inner.minX, y: inner.minY + Self.headerHeight, width: width, height: 1)
        var y = inner.minY + Self.headerHeight + 1
        for view in rowViews {
            view.frame = CGRect(x: inner.minX, y: y, width: width, height: Self.rowHeight + (view.hasBorder ? 1 : 0))
            view.layoutColumns(first: Self.firstColumn, column: column)
            y += Self.rowHeight + 1
        }
    }

    /// One row: `hover:bg-accent/50`, and `bg-muted/20` on every other one
    private final class RowView: UIView {
        let hasBorder: Bool
        private let isStriped: Bool
        private let nameLabel = UILabel()
        private let cellLabels: [UILabel]
        private let nameBackground = UIView()
        private let divider = UIView()
        private let rule = UIView()

        init(row: Row, isStriped: Bool, hasBorder: Bool) {
            self.isStriped = isStriped
            self.hasBorder = hasBorder
            cellLabels = row.cells.map { cell in
                let label = UILabel()
                label.attributedText = CSSText.string(cell.text, font: UIFont.nunito(ofSize: 12, weight: cell.medium ? .medium : .regular).tabular,
                                                      color: cell.color, lineHeight: 16, alignment: .right,
                                                      lineBreak: .byClipping)
                return label
            }
            super.init(frame: .zero)
            // the sticky first column is `bg-background`, over the stripe
            nameBackground.backgroundColor = UIColor.HayaseTheme.background
            addSubview(nameBackground)
            nameLabel.attributedText = CSSText.string(row.name, font: .nunito(ofSize: 12, weight: .medium),
                                                      color: UIColor.HayaseTheme.foreground, lineHeight: 16,
                                                      lineBreak: .byTruncatingTail)
            addSubview(nameLabel)
            cellLabels.forEach { addSubview($0) }
            divider.backgroundColor = UIColor.HayaseTheme.border.withAlphaComponent(0.5)   // `border-r border-border/50`
            addSubview(divider)
            rule.backgroundColor = UIColor.HayaseTheme.border                              // `border-b`
            rule.isHidden = !hasBorder
            addSubview(rule)
            backgroundColor = isStriped ? UIColor.HayaseTheme.muted.withAlphaComponent(0.2) : .clear
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
        }

        required init?(coder: NSCoder) {
            nil
        }

        func layoutColumns(first: CGFloat, column: CGFloat) {
            nameBackground.frame = CGRect(x: 0, y: 0, width: first, height: DebugMatrixView.rowHeight)
            nameLabel.frame = CGRect(x: 8, y: 0, width: first - 17, height: DebugMatrixView.rowHeight)
            divider.frame = CGRect(x: first - 1, y: 0, width: 1, height: DebugMatrixView.rowHeight)
            for (index, label) in cellLabels.enumerated() {
                let last = index == cellLabels.count - 1
                label.frame = CGRect(x: first + CGFloat(index) * column + 8, y: 0,
                                     width: max(0, column - (last ? 28 : 16)), height: DebugMatrixView.rowHeight)
            }
            rule.frame = CGRect(x: 0, y: DebugMatrixView.rowHeight, width: bounds.width, height: 1)
        }

        @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
            let hovering = recognizer.state == .began || recognizer.state == .changed
            UIView.animate(withDuration: 0.15) {
                self.backgroundColor = hovering ? UIColor.HayaseTheme.accent.withAlphaComponent(0.5)
                    : (self.isStriped ? UIColor.HayaseTheme.muted.withAlphaComponent(0.2) : .clear)
            }
        }
    }
}

// MARK: - Helpers

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}

private extension UIFont {
    /// `font-variant-numeric: tabular-nums`
    var tabular: UIFont {
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [[
            .featureIdentifier: kNumberSpacingType,
            .typeIdentifier: kMonospacedNumbersSelector,
        ]]
        return UIFont(descriptor: fontDescriptor.addingAttributes([.featureSettings: features]), size: pointSize)
    }
}
