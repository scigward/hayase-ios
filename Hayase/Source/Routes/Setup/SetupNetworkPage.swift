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

import Foundation
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
        speedInput.input.pressScaleTarget = speedInput      // `no-scale` in a `scale-parent`
        let speedCard = SettingsCardView(
            title: "Transfer Speed Limit",
            description: "Download/Upload speed limit for torrents, higher values increase CPU usage, and values higher than your storage write speeds will quickly fill up RAM.",
            control: speedInput, transparent: true, topAlignedControl: true)
        speedCard.labelTarget = speedInput

        // Max Number of Connections
        bind(maxConnsInput, key: Self.maxConnsKey, fallback: "80", range: 1...512)
        maxConnsInput.input.pressScaleTarget = maxConnsInput.input
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
        portInput.input.pressScaleTarget = portInput.input
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

// MARK: - SetupSpeedTest

//  Mirrors: the module-level `speedTest` and `downloadBandwidthCheck` of src/routes/setup/network/+page.svelte
//
//    const speedTest = new SpeedTest({ autoStart: false, measurements: [{ type: 'download', bytes: 2.5e7, count: 4 }] })
//
//  which is @cloudflare/speedtest 1.13: four downloads of 25MB from speed.cloudflare.com, one after
//  the other, each timed from the first byte (`ping`, the time to first byte less the server's own
//  time from `Server-Timing`, plus the time the payload took), and the bandwidth of the test the 90th
//  percentile of the speeds of the requests that took 10ms or more. A request that fails is tried
//  again, up to 20 times in a row, and then the test ends with what it has.
//
//  The test belongs to the app, not to the page: it goes on when the page is left, and it is run
//  once, so coming back to the page shows the same result (`play()` on a finished test does nothing).
//  The speedtest package also reports its result to Cloudflare (`logAimApiUrl`), which is not ported.

final class SetupSpeedTest: NSObject {
    static let shared = SetupSpeedTest()

    /// `downloadBandwidthCheck`
    let check = SetupCheck(title: "Network Speed", pending: "Checking network speed...")

    private struct Timing {
        let duration: Double   // ms
        let bps: Double?
    }

    private static let downloadURL = "https://speed.cloudflare.com/__down"
    private static let bytes = 25_000_000
    private static let count = 4
    private static let maxRetries = 20
    private static let estimatedHeaderFraction = 0.005
    private static let bandwidthMinRequestDuration = 10.0
    private static let bandwidthPercentile = 0.9

    private let work = DispatchQueue(label: "app.hayase.setup-speed-test")
    private lazy var delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = work
        return queue
    }()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }()

    private var isRunning = false
    private var isFinished = false
    private var counter = 0
    private var retries = 0
    private var timings: [Timing] = []
    private var measurementID = ""
    private var serverTime: Double?
    private var responseWasOK = true
    private var metrics: URLSessionTaskMetrics?

    private override init() {
        super.init()
    }

    /// `if (!speedTest.isRunning) speedTest.play()`
    func play() {
        work.async { [self] in
            guard !isRunning, !isFinished else { return }
            isRunning = true
            counter = 0
            retries = 0
            timings = []
            measurementID = String(Int((Double.random(in: 0..<1) * 1e16).rounded()))
            next()
        }
    }

    // MARK: Measurement

    private func next() {
        guard counter < Self.count else {
            finish()
            return
        }
        var components = URLComponents(string: Self.downloadURL)
        components?.queryItems = [URLQueryItem(name: "measId", value: measurementID),
                                  URLQueryItem(name: "bytes", value: String(Self.bytes))]
        guard let url = components?.url else {
            finish()
            return
        }
        serverTime = nil
        responseWasOK = true
        metrics = nil
        session.dataTask(with: URLRequest(url: url)).resume()
    }

    /// The `.catch` of the engine: another go at the same request, until it has been 20 in a row.
    private func failed() {
        if retries < Self.maxRetries {
            retries += 1
            next()
        } else {
            retries = 0
            finish()
        }
    }

    private func finish() {
        isRunning = false
        isFinished = true
        let speeds = timings
            .filter { $0.duration >= Self.bandwidthMinRequestDuration }
            .compactMap { $0.bps }
            .filter { $0 != 0 }
        let bandwidth = Self.percentile(speeds, Self.bandwidthPercentile)
        let shown = TorrentFormat.fastPrettyBits(UInt64(max(0, bandwidth)))
        if bandwidth < 1.5e+7 {
            check.resolve(.init(status: .error,
                                text: "Download speed is \(shown)/s, at least 15Mb/s download is required to stream video real-time."))
        } else if bandwidth < 2.5e+7 {
            check.resolve(.init(status: .warning, text: "Download speed is \(shown)/s, 25Mb/s download is recommended."))
        } else {
            check.resolve(.init(status: .success, text: "Download speed is \(shown)/s."))
        }
    }

    /// The value at a percentile, by linear interpolation (`percentile` of numbers.ts).
    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Double(values.count - 1) * percentile
        let remainder = index.truncatingRemainder(dividingBy: 1)
        if remainder == 0 { return sorted[Int(index.rounded())] }
        let low = sorted[Int(index.rounded(.down))]
        let high = sorted[Int(index.rounded(.up))]
        return low + (high - low) * remainder
    }

    /// `cfGetServerTime`: the server's own time from `Server-Timing`, in ms.
    private static func serverTime(of response: HTTPURLResponse) -> Double? {
        guard let header = response.value(forHTTPHeaderField: "Server-Timing") else { return nil }
        let range = NSRange(header.startIndex..., in: header)
        if let regex = try? NSRegularExpression(pattern: #"(?:^|,\s*)cfReq(?:uest)?Dur(?:ation)?;\s*dur=([0-9.]+)"#,
                                                options: .caseInsensitive),
           let match = regex.firstMatch(in: header, range: range),
           let duration = Range(match.range(at: 1), in: header).flatMap({ Double(header[$0]) }),
           duration > 0.01 {
            return duration
        }
        var sum = 0.0
        if let regex = try? NSRegularExpression(pattern: #"(?:^|,\s*)cfSpeed[a-zA-Z]*;\s*dur=([0-9.]+)"#,
                                                options: .caseInsensitive) {
            for match in regex.matches(in: header, range: range) {
                if let duration = Range(match.range(at: 1), in: header).flatMap({ Double(header[$0]) }) {
                    sum += duration
                }
            }
        }
        return sum > 0.01 ? sum : nil
    }

    private func recordTiming() {
        let transaction = metrics?.transactionMetrics.last
        let ttfb = Self.milliseconds(from: transaction?.requestStartDate, to: transaction?.responseStartDate)
        var payload = Self.milliseconds(from: transaction?.responseStartDate, to: transaction?.responseEndDate)
        if transaction?.responseStartDate == nil, let interval = metrics?.taskInterval {
            payload = interval.duration * 1000
        }
        let transferSize = Double((transaction?.countOfResponseBodyBytesReceived ?? 0)
                                  + (transaction?.countOfResponseHeaderBytesReceived ?? 0))
        let baseServerTime = serverTime ?? 0
        var ping = ttfb - baseServerTime
        // Discard the adjustment if it would collapse the ping
        if ping <= 1 { ping = max(0, ttfb - baseServerTime) }
        let duration = ping + payload
        let bits = 8 * (transferSize != 0 ? transferSize : Double(Self.bytes) * (1 + Self.estimatedHeaderFraction))
        let seconds = duration / 1000
        timings.append(Timing(duration: duration, bps: seconds == 0 ? nil : bits / seconds))
        counter += 1
        retries = 0
    }

    private static func milliseconds(from start: Date?, to end: Date?) -> Double {
        guard let start, let end else { return 0 }
        return end.timeIntervalSince(start) * 1000
    }
}

extension SetupSpeedTest: URLSessionDataDelegate {
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            // `if (r.ok) return r; throw Error(r.statusText)`
            responseWasOK = (200..<300).contains(http.statusCode)
            serverTime = Self.serverTime(of: http)
        }
        completionHandler(.allow)
    }

    /// The payload is only timed.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {}

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        self.metrics = metrics
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil || !responseWasOK {
            failed()
        } else {
            recordTiming()
            next()
        }
    }
}
