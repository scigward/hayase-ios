//
//  TorrentFormat.swift
//  Hayase
//
//  The number formats and the dot and badge views of the torrent client page.
//

import UIKit

enum TorrentFormat {
    static func makeDotLabel() -> UIView {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 8),
            v.heightAnchor.constraint(equalToConstant: 8),
        ])
        return v
    }

    // MARK: - Format helpers (Hayase-compatible: SI units, 1000 divisor)

    /// Formats bytes using SI units (1000 divisor): B → kB → MB → GB → TB
    static func fastPrettyBytes(_ bytes: UInt64) -> String {
        prettySI(bytes, units: ["B", "kB", "MB", "GB", "TB"])
    }

    /// Formats bits using SI units (1000 divisor): b → kb → Mb → Gb → Tb
    /// (No /s suffix — callers append it as in Hayase's `{fastPrettyBits(...)}/s`)
    static func fastPrettyBits(_ bits: UInt64) -> String {
        prettySI(bits, units: ["b", "kb", "Mb", "Gb", "Tb"])
    }

    private static func prettySI(_ value: UInt64, units: [String]) -> String {
        var amount = Double(value)
        var index = 0
        while amount >= 1000 && index < units.count - 1 { amount /= 1000; index += 1 }
        // interface Number(toFixed(1)) drops a trailing .0; do not localize decimals.
        let rounded = (amount * 10).rounded() / 10
        let text = String(format: rounded.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f",
                          locale: Locale(identifier: "en_US_POSIX"), rounded)
        return text + " " + units[index]
    }

    /// Formats seconds into up to 2 largest time units: "22y 5mo", "1h 2m", "2m 3s", "0s"
    static func eta(seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        let units: [(String, Int)] = [
            ("y", 31_536_000), ("mo", 2_592_000), ("d", 86_400),
            ("h", 3_600), ("m", 60), ("s", 1),
        ]
        var remaining = seconds
        var parts: [String] = []
        for (suffix, divisor) in units {
            guard parts.count < 2 else { break }
            let count = remaining / divisor
            if count > 0 {
                parts.append("\(count)\(suffix)")
                remaining %= divisor
            }
        }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }

    /// Overload: computes ETA from remaining bytes and download rate, then formats.
    static func eta(remaining: UInt64, rate: UInt64) -> String {
        guard rate > 0, remaining > 0 else { return "0s" }
        return eta(seconds: Int(clamping: remaining / rate))
    }
}

// MARK: - TorrentPillBadge

/// Pill-shaped badge label with proper internal padding (used for Downloading/Seeding status).
/// Matches the existing ThreadBadgeLabel / PaddedBadgeLabel pattern.
final class TorrentPillBadge: UILabel {
    private let hPad: CGFloat
    private let vPad: CGFloat

    init(horizontalPadding: CGFloat = 10, verticalPadding: CGFloat = 4) {
        self.hPad = horizontalPadding
        self.vPad = verticalPadding
        super.init(frame: .zero)
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        self.hPad = 10
        self.vPad = 4
        super.init(coder: coder)
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: hPad, dy: vPad))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + hPad * 2, height: s.height + vPad * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
