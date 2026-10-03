//
//  SetupNetworkPage.swift
//  Hayase
//
//  Mirrors: src/routes/setup/network/+page.svelte
//
//    <Progress step={1} />
//    <div class='space-y-3 lg:max-w-4xl pt-5 h-full overflow-y-auto'>
//      Streamed Download · Transfer Speed Limit · Max Number of Connections · Forwarded Torrent Port
//      {#if !SUPPORTS.isIOS} Use DNS Over HTTPS · DNS Over HTTPS URL {/if}
//    </div>
//    <Footer step={1} {checks}><div class='contents' on:click={openURL(…#port-forwarding)}><CircleHelp class='size-4 ml-2 shrink-0 inline cursor-pointer text-blue-500 border-b border-blue-500' /></div></Footer>
//
//  The DNS over HTTPS cards are not on iOS, which is what the app is. The page starts the speed test
//  once for the whole app (`if (!speedTest.isRunning) speedTest.play()`), and checks the port the
//  torrent client is given, again whenever that port changes.
//

import UIKit

final class SetupNetworkPage: SetupStepView {
    private static let torrentSpeedKey = "pref_torrentSpeed"
    private static let maxConnsKey = "pref_maxConns"
    private static let torrentPortKey = "pref_torrentPort"
    private static let portHelpURL = "https://thewiki.moe/getting-started/torrenting/#port-forwarding"

    private let maxConnsInput: SettingsInputControl
    private var port: Int
    private var portCheck: SetupCheck?
    private var settingsObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        maxConnsInput = SettingsInputControl(value: defaults.string(forKey: Self.maxConnsKey) ?? "80",
                                             placeholder: "80", width: 128, numeric: true)
        port = Int(defaults.string(forKey: Self.torrentPortKey) ?? "0") ?? 0
        super.init(step: 1, topPadding: 20, bottomPadding: 0)   // pt-5

        // `if (!speedTest.isRunning) speedTest.play()`
        SetupSpeedTest.shared.play()

        // Streamed Download
        let streamed = HayaseSwitch()
        streamed.setOn(Settings.streamedDownload, animated: false)
        streamed.addAction(UIAction { [weak streamed] _ in
            guard let streamed else { return }
            Settings.write(streamed.isOn, forKey: Settings.Keys.streamedDownload)
            TorrentBackendManager.shared.applyCurrentSettings()
        }, for: .valueChanged)
        let streamedCard = SettingsCardView(
            title: "Streamed Download",
            description: "Only downloads the data that's directly needed for playback, down to the minute, instead of downloading an entire batch of episodes. Will not buffer ahead more than a few seconds, and will stop downloading once the few second buffer is filled. Saves bandwidth and reduces strain on the peer swarm.",
            control: streamed, transparent: true)
        streamedCard.labelTarget = streamed

        // Transfer Speed Limit: the field is in a box with its own border (`border border-input rounded-md self-baseline`),
        // which makes it 130pt across, and the box is `self-baseline`, so it sits at the top of the card's row.
        let speedInput = SettingsInputControl(value: defaults.string(forKey: Self.torrentSpeedKey) ?? "40",
                                              placeholder: "40", width: 130, numeric: true, suffix: "Mb/s")
        bind(speedInput, key: Self.torrentSpeedKey, fallback: "40", range: 1...50, allowsFraction: true)
        let speedCard = SettingsCardView(
            title: "Transfer Speed Limit",
            description: "Download/Upload speed limit for torrents, higher values increase CPU usage, and values higher than your storage write speeds will quickly fill up RAM.",
            control: speedInput, transparent: true, topAlignedControl: true)
        speedCard.labelTarget = speedInput

        // Max Number of Connections
        bind(maxConnsInput, key: Self.maxConnsKey, fallback: "80", range: 1...512)
        let connsCard = SettingsCardView(
            title: "Max Number of Connections",
            description: "Number of peers per torrent. Higher values will increase download speeds but might quickly fill up available ports if your ISP limits the maximum allowed number of open connections.",
            control: maxConnsInput, transparent: true)
        connsCard.labelTarget = maxConnsInput

        // Forwarded Torrent Port (`max='65536'` on the page; 65535 is the last port there is)
        let portInput = SettingsInputControl(value: defaults.string(forKey: Self.torrentPortKey) ?? "0",
                                             placeholder: "0", width: 128, numeric: true)
        bind(portInput, key: Self.torrentPortKey, fallback: "0", range: 0...65535) { [weak self] in
            self?.portMayHaveChanged()
        }
        let portCard = SettingsCardView(
            title: "Forwarded Torrent Port",
            description: "Forwarded port used for incoming torrent connections. 0 automatically finds an open unused port. Change this to a specific port if you forwarded manually, or if you use a VPN.",
            control: portInput, transparent: true)
        portCard.labelTarget = portInput

        setContent([streamedCard, speedCard, connsCard, portCard])

        // <Footer step={1} {checks}> with its slot
        footer.slotProvider = { slot in slot == "port" ? Self.makeHelpIcon() : nil }
        refreshChecks()

        // `$settings.maxConns = 200` shows in the field it is bound to
        settingsObserver = NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] note in
            guard let self, note.userInfo?["key"] as? String == Self.maxConnsKey,
                  !self.maxConnsInput.input.isFirstResponder else { return }
            self.maxConnsInput.input.text = UserDefaults.standard.string(forKey: Self.maxConnsKey) ?? "80"
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    // MARK: Inputs

    /// `bind:value={$settings.…}` of a number input: a number that is allowed is kept as it is typed, and
    /// what is left in the field when it is let go of is made one.
    private func bind(_ input: SettingsInputControl, key: String, fallback: String, range: ClosedRange<Int>,
                      allowsFraction: Bool = false, changed: (() -> Void)? = nil) {
        input.onChange = { value in
            guard let number = Double(value), number.isFinite,
                  number >= Double(range.lowerBound), number <= Double(range.upperBound),
                  allowsFraction || Int(value) != nil else { return }
            Settings.write(value, forKey: key)
            TorrentBackendManager.shared.applyCurrentSettings()
            changed?()
        }
        input.onCommit = { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: String
            if allowsFraction, let number = Double(trimmed), number.isFinite {
                result = String(min(max(number, Double(range.lowerBound)), Double(range.upperBound)))
            } else if let number = Int(trimmed) {
                result = String(min(max(number, range.lowerBound), range.upperBound))
            } else {
                return UserDefaults.standard.string(forKey: key) ?? fallback
            }
            Settings.write(result, forKey: key)
            TorrentBackendManager.shared.applyCurrentSettings()
            changed?()
            return result
        }
    }

    // MARK: Checks

    /// `$: port = $settings.torrentPort`: a new port is a new check, one that is not made for the same port twice.
    private func portMayHaveChanged() {
        let current = Int(UserDefaults.standard.string(forKey: Self.torrentPortKey) ?? "0") ?? 0
        guard current != port else { return }
        port = current
        refreshChecks()
    }

    /// `$: checks = [downloadBandwidthCheck, { promise: checkPortAvailability(port), … }]`
    private func refreshChecks() {
        let check = checkPortAvailability(port)
        portCheck = check
        footer.setChecks([SetupSpeedTest.shared.check, check])
    }

    /// `checkPortAvailability`: whether the port can be reached from outside, which the torrent client says.
    private func checkPortAvailability(_ port: Int) -> SetupCheck {
        let check = SetupCheck(title: "Port Forwarding", pending: "Checking port forwarding availability...")
        TorrentBackendManager.shared.webTorrentCheckIncomingConnections(port: port) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let available):
                    SetupFlow.hasPortForwarding = available
                    if available {
                        Settings.write("200", forKey: Self.maxConnsKey)
                        TorrentBackendManager.shared.applyCurrentSettings()
                        check.resolve(.init(status: .success, text: "Port forwarding is available."))
                    } else {
                        check.resolve(.init(status: .error,
                                            text: "Not available. Peer discovery will suffer. Streaming old, poorly seeded anime might be impossible.",
                                            slot: "port"))
                    }
                case .failure(let error):
                    check.resolve(.init(status: .error,
                                        text: "Failed to check port forwarding availability. " + error.localizedDescription,
                                        slot: "port"))
                }
            }
        }
        return check
    }

    /// `<CircleHelp class='size-4 ml-2 shrink-0 inline cursor-pointer text-blue-500 border-b border-blue-500' />`
    private static func makeHelpIcon() -> UIView {
        SetupHelpIcon(url: portHelpURL)
    }
}

/// A 16pt square whose bottom 1pt is a `border-b`, which leaves the icon the 15pt over it (the border is
/// inside a `size-4`), in `text-blue-500`; it opens the page about port forwarding.
private final class SetupHelpIcon: UIControl {
    private static let blue = UIColor(red: 0x3b / 255.0, green: 0x82 / 255.0, blue: 0xf6 / 255.0, alpha: 1)   // blue-500

    private let icon = UIImageView(image: UIImage.hayaseIcon("circle-question-mark", pointSize: 15))
    private let border = UIView()

    init(url: String) {
        super.init(frame: .zero)
        icon.tintColor = Self.blue
        icon.contentMode = .scaleAspectFit
        border.backgroundColor = Self.blue
        addSubview(icon)
        addSubview(border)
        isAccessibilityElement = true
        accessibilityLabel = "Port forwarding help"
        accessibilityTraits = .link
        addAction(UIAction { _ in
            if let url = URL(string: url) { UIApplication.shared.open(url) }
        }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = CGRect(x: 0.5, y: 0, width: 15, height: 15)
        border.frame = CGRect(x: 0, y: 15, width: 16, height: 1)
    }
}
