// Shared table measurements: CSS content widths plus each cell's horizontal padding.
import UIKit

enum TorrentClientColumnWidths {
    static func files(entries: [WebTorrentFileInfo]) -> [CGFloat?] {
        files(sizes: entries.map { TorrentFormat.fastPrettyBytes($0.size) },
              streams: entries.map(\.selections))
    }

    static func files(sizes: [String], streams: [Int]) -> [CGFloat?] {
        [nil, measured("Size", values: sizes), 128,
         measured("Streams", values: streams.map(String.init))]
    }

    static func library(entries: [WebTorrentLibraryEntry]) -> [CGFloat?] {
        let dates = entries.map { TorrentClientLibraryDate($0.date) }
        let dateWidth = max(measured("Date", values: []), dates.map {
            textWidth($0.text, font: .nunito(ofSize: 14)) + ($0.warning == nil ? 0 : 20)
        }.max() ?? 0)
        // min-w-72 applies to the td border box. First padding is 24 + 16;
        // Torrent Name is 16 + 16. The checkbox itself is an 18pt border box.
        return [248, measured("Episode", values: entries.map { $0.episode.map(String.init) ?? "?" }),
                measured("Files", values: entries.map { String($0.files) }),
                measured("Size", values: entries.map { $0.size == 0 ? "?" : TorrentFormat.fastPrettyBytes($0.size) }),
                max(measured("Status", values: ["?"]),
                    max(textWidth("In Progress", font: .nunito(ofSize: 14)) + 16,
                        textWidth("Completed", font: .nunito(ofSize: 14)) + 16)),
                dateWidth, nil, 18]
    }

    static func minimumTableWidth(_ widths: [CGFloat?], flexibleMinimums: [Int: CGFloat],
                                  hasSelectionColumn: Bool = false) -> CGFloat {
        widths.enumerated().reduce(CGFloat(0)) { $0 + ($1.element ?? flexibleMinimums[$1.offset] ?? 0) }
            + CGFloat(max(0, widths.count - 1)) * 32 + (hasSelectionColumn ? 40 : 48)
    }

    static var filesNameMinimum: CGFloat { textWidth("File Name", font: .nunito(ofSize: 14, weight: .medium)) }
    static let libraryNameMinimum: CGFloat = 256

    private static func measured(_ header: String, values: [String]) -> CGFloat {
        max(textWidth(header, font: .nunito(ofSize: 14, weight: .medium)),
            values.map { textWidth($0, font: .nunito(ofSize: 14)) }.max() ?? 0)
    }
    private static func textWidth(_ value: String, font: UIFont) -> CGFloat {
        ceil((value as NSString).size(withAttributes: [.font: font]).width)
    }
}

struct TorrentClientLibraryDate {
    let text: String
    let warning: String?
    let color: UIColor

    init(_ timestamp: TimeInterval?, now: Date = Date()) {
        guard let timestamp, timestamp > 0 else {
            text = "?"; warning = nil; color = TorrentClientStyle.foreground
            return
        }
        let date = Date(timeIntervalSince1970: timestamp / (timestamp > 10_000_000_000 ? 1000 : 1))
        let formatter = DateFormatter()
        // toLocaleDateString uses the locale's order and a full numeric year.
        formatter.setLocalizedDateFormatFromTemplate("yMd")
        text = formatter.string(from: date)
        let age = now.timeIntervalSince(date)
        if age > 30 * 24 * 60 * 60 {
            color = UIColor(red: 248 / 255, green: 113 / 255, blue: 113 / 255, alpha: 1) // red-400
            warning = "Played more than 30 days ago.\nCached metadata might have expired.\nPlay this torrent again to refresh."
        } else if age > 21 * 24 * 60 * 60 {
            color = UIColor(red: 254 / 255, green: 240 / 255, blue: 138 / 255, alpha: 1) // yellow-200
            warning = "Played more than 21 days ago.\nCached metadata might soon expire."
        } else {
            color = TorrentClientStyle.foreground
            warning = nil
        }
    }
}
