//
//  StreamingLogger.swift
//  TheAnimeTool
//
//  A lightweight in-app logger that captures streaming, torrent, and player
//  errors/warnings and presents them as an overlay in the video player UI.
//  Errors auto-fade after a configurable duration. Older entries are evicted
//  when the maximum capacity is reached.
//

import UIKit

// MARK: - Log entry model

/// A single log entry with timestamp, severity, and message.
struct StreamingLogEntry {
    enum Level: String {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
    }

    let timestamp: Date
    let level: Level
    let message: String

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }

    var displayString: String {
        "[\(formattedTime)] \(level.rawValue): \(message)"
    }
}

// MARK: - StreamingLogger

/// Thread-safe singleton logger that captures streaming/torrent/player events.
/// Subscribe to `entriesDidChange` to update UI when new entries arrive.
final class StreamingLogger {

    static let shared = StreamingLogger()

    /// Posted on the main thread whenever entries change.
    static let entriesDidChange = Notification.Name("StreamingLoggerEntriesDidChange")

    /// Maximum number of retained entries. Oldest are evicted first.
    private let maxEntries = 200

    /// Thread-safe storage.
    private let lock = NSLock()
    private var _entries: [StreamingLogEntry] = []

    /// Current snapshot of all entries (newest last).
    var entries: [StreamingLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    private init() {}

    // MARK: - Public API

    func info(_ message: String) {
        append(.init(timestamp: Date(), level: .info, message: message))
    }

    func warn(_ message: String) {
        append(.init(timestamp: Date(), level: .warn, message: message))
    }

    func error(_ message: String) {
        append(.init(timestamp: Date(), level: .error, message: message))
    }

    func clear() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.entriesDidChange, object: nil)
        }
    }

    // MARK: - Private

    private func append(_ entry: StreamingLogEntry) {
        lock.lock()
        _entries.append(entry)
        if _entries.count > maxEntries {
            _entries.removeFirst(_entries.count - maxEntries)
        }
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.entriesDidChange, object: nil)
        }
    }
}

// MARK: - LogOverlayView

/// A translucent overlay that displays streaming log entries at the bottom-left
/// of the video player. Shows the most recent entries with color-coded severity.
/// Tap the overlay to expand/collapse; long-press to copy all entries.
final class LogOverlayView: UIView {

    /// Maximum visible lines in collapsed mode.
    private let collapsedLineCount = 3

    /// Maximum visible lines in expanded mode.
    private let expandedLineCount = 15

    /// How long error/warn entries stay visible before auto-fading (seconds).
    private let autoHideDelay: TimeInterval = 8.0

    /// Estimated height per monospaced log line (points).
    private static let lineHeight: CGFloat = 14

    /// Vertical padding above and below the text content (points).
    private static let verticalPadding: CGFloat = 8

    private let textView = UITextView()
    private var isExpanded = false
    private var autoHideWork: DispatchWorkItem?
    private var heightConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 6
        clipsToBounds = true
        isHidden = true // hidden until first entry

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        textView.isUserInteractionEnabled = false
        addSubview(textView)

        heightConstraint = heightAnchor.constraint(equalToConstant: collapsedHeight)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightConstraint,
        ])

        // Gestures
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleExpand))
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(copyLogs))
        addGestureRecognizer(longPress)

        // Observe log changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(onEntriesChanged),
            name: StreamingLogger.entriesDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout helpers

    private var collapsedHeight: CGFloat { CGFloat(collapsedLineCount) * Self.lineHeight + Self.verticalPadding }
    private var expandedHeight: CGFloat  { CGFloat(expandedLineCount) * Self.lineHeight + Self.verticalPadding }

    // MARK: - Update

    @objc private func onEntriesChanged() {
        let entries = StreamingLogger.shared.entries

        // Only show errors and warnings in the overlay (info is background noise)
        let visible = entries.filter { $0.level == .error || $0.level == .warn }
        guard !visible.isEmpty else {
            isHidden = true
            return
        }

        // Build attributed string with color-coded lines
        let maxLines = isExpanded ? expandedLineCount : collapsedLineCount
        let tail = visible.suffix(maxLines)
        let attributed = NSMutableAttributedString()
        for (i, entry) in tail.enumerated() {
            let color: UIColor
            switch entry.level {
            case .error: color = UIColor.systemRed
            case .warn:  color = UIColor.systemYellow
            case .info:  color = UIColor.white
            }
            let line = entry.displayString + (i < tail.count - 1 ? "\n" : "")
            attributed.append(NSAttributedString(
                string: line,
                attributes: [
                    .foregroundColor: color,
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                ]))
        }
        textView.attributedText = attributed
        isHidden = false

        // Auto-hide after delay
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        autoHideWork?.cancel()
        guard !isExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) { self?.alpha = 0.0 }
        }
        autoHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: work)
        // Restore visibility if we were faded out
        UIView.animate(withDuration: 0.15) { self.alpha = 1.0 }
    }

    // MARK: - Actions

    @objc private func toggleExpand() {
        isExpanded.toggle()
        heightConstraint.constant = isExpanded ? expandedHeight : collapsedHeight
        textView.isScrollEnabled = isExpanded
        textView.isUserInteractionEnabled = isExpanded
        UIView.animate(withDuration: 0.2) { self.superview?.layoutIfNeeded() }
        onEntriesChanged() // refresh visible lines
        if isExpanded {
            autoHideWork?.cancel()
            UIView.animate(withDuration: 0.15) { self.alpha = 1.0 }
        } else {
            scheduleAutoHide()
        }
    }

    @objc private func copyLogs(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let all = StreamingLogger.shared.entries.map(\.displayString).joined(separator: "\n")
        UIPasteboard.general.string = all

        // Brief visual feedback
        let originalBg = backgroundColor
        backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        UIView.animate(withDuration: 0.5) { self.backgroundColor = originalBg }
    }
}
