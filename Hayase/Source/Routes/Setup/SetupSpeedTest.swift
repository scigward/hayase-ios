//
//  SetupSpeedTest.swift
//  Hayase
//
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
//

import Foundation

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
