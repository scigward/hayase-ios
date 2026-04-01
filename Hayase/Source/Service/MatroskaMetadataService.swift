import Foundation
import MatroskaSwift

/// Parses MKV container headers to extract accurate subtitle track language codes.
///
/// MPV reads subtitle tracks from MKV files but sometimes reports missing or
/// inaccurate language metadata (especially during streaming when the full
/// header hasn't been buffered). This service uses `matroska-swift` to parse
/// the raw MKV TrackEntry elements and extract the Language field directly,
/// providing a reliable track-number → language mapping.
///
/// Everything else (font extraction, subtitle rendering, chapter parsing,
/// attachment handling) is handled natively by MPV.
final class MatroskaMetadataService {

    static let shared = MatroskaMetadataService()

    /// Cached language maps keyed by file URL to avoid re-parsing.
    private var cache: [URL: [Int: String]] = [:]

    private let queue = DispatchQueue(label: "com.hayase.matroska-lang", attributes: .concurrent)

    private init() {}

    // MARK: - Public API

    /// Parses the MKV header at `fileURL` and returns a mapping of
    /// subtitle track number → language code (e.g. `[3: "eng", 4: "jpn"]`).
    ///
    /// The language codes come directly from the Matroska Language element
    /// in each subtitle TrackEntry, which is the most authoritative source.
    /// Results are cached per file URL to avoid re-parsing.
    func subtitleLanguages(for fileURL: URL) -> [Int: String] {
        // Check cache first (concurrent read)
        if let cached = queue.sync(execute: { cache[fileURL] }) {
            return cached
        }

        // Parse on current thread, then cache with barrier write
        let parser = MatroskaSubtitleParser()
        let result: MatroskaSubtitles
        do {
            result = try parser.parse(fileAt: fileURL)
        } catch {
            Logger.shared.log("MatroskaMetadataService: failed to parse \(fileURL.lastPathComponent): \(error)", type: "Error")
            return [:]
        }

        var langMap: [Int: String] = [:]
        for track in result.tracks {
            if let lang = track.language, !lang.isEmpty, lang != "und" {
                langMap[track.number] = lang
            }
        }

        queue.async(flags: .barrier) { [weak self] in
            self?.cache[fileURL] = langMap
        }

        return langMap
    }

    /// Clears all cached language data.
    func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
}
