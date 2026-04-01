import Foundation
import MatroskaSwift

/// Swift port of `attachments.ts` from the Hayase web torrent-client.
///
/// The web version uses the npm `matroska-metadata` package to:
///   • Extract font/image attachments from MKV/WebM files
///   • Extract subtitle tracks and stream subtitles via callbacks
///   • Extract chapter markers
///   • Extract track metadata (audio, video, subtitle tracks)
///
/// This service replicates that functionality using `matroska-swift`,
/// the Swift port of the same underlying matroska parsing library.
final class MatroskaMetadataService {

    static let shared = MatroskaMetadataService()

    // MARK: - Types (mirroring web's `native` interface)

    /// Font or image attachment embedded in a Matroska container.
    /// Mirrors the web's `Attachment` type from `native/index.ts`.
    struct MKVAttachment {
        let filename: String
        let mimetype: String
        let id: Int
        let data: Data
    }

    /// Track metadata extracted from the Matroska container.
    /// Mirrors the web's `tracks()` return type.
    struct MKVTrack {
        let number: String
        let language: String?
        let type: String
        let header: String?
        let name: String?
    }

    /// Chapter marker extracted from the Matroska container.
    /// Mirrors the web's `chapters()` return type.
    struct MKVChapter {
        let start: Double   // milliseconds
        let end: Double     // milliseconds
        let text: String
    }

    /// Subtitle entry delivered via streaming callback.
    /// Mirrors the web's `subtitles()` callback signature.
    struct MKVSubtitle {
        let text: String
        let time: Double      // milliseconds
        let duration: Double  // milliseconds
    }

    // MARK: - Internal State (mirrors web's filemap + metadatamap)

    /// Maps `hash + id` → file URL on disk, mirroring web's `this.filemap`.
    private var fileMap: [String: URL] = [:]

    /// Maps file URL → parsed matroska result, mirroring web's `this.metadatamap`.
    private var metadataMap: [URL: MatroskaSubtitles] = [:]

    /// Directory where extracted font attachments are written.
    /// MPV reads fonts from this directory via `--sub-fonts-dir`.
    private(set) var fontsDirectory: URL

    private let queue = DispatchQueue(label: "com.hayase.matroska-metadata", attributes: .concurrent)

    /// File extensions recognised as font attachments.
    private static let fontExtensions: Set<String> = ["ttf", "otf", "woff", "woff2"]

    /// MIME types recognised as font attachments.
    private static let fontMimeTypes: Set<String> = [
        "font/ttf", "font/otf", "font/woff", "font/woff2",
        "application/x-truetype-font", "application/vnd.ms-opentype",
        "application/font-sfnt", "application/font-woff"
    ]

    /// Returns `true` when `filename` or `mimetype` indicate a font file.
    private static func isFontAttachment(filename: String, mimetype: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        if fontExtensions.contains(ext) { return true }
        if fontMimeTypes.contains(mimetype) { return true }
        if mimetype.contains("font") { return true }
        return false
    }

    private init() {
        let tmpBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("hayase-fonts", isDirectory: true)
        self.fontsDirectory = tmpBase
        try? FileManager.default.createDirectory(at: tmpBase, withIntermediateDirectories: true)
    }

    // MARK: - Register (mirrors web's `attachments.register()`)

    /// Registers file paths for metadata extraction, exactly like the web version:
    ///
    /// ```js
    /// // web: attachments.ts
    /// register(files, hash) {
    ///     this.filemap.clear()
    ///     files.forEach((file, id) => {
    ///         if (file.name.endsWith('.mkv') || file.name.endsWith('.webm')) {
    ///             this.filemap.set(hash + id, file)
    ///         }
    ///     })
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - files: Array of `(name, url)` tuples for each file in the torrent.
    ///   - hash: The torrent info hash.
    func register(files: [(name: String, url: URL)], hash: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.fileMap.removeAll()
            self.metadataMap.removeAll()
            // Clean old extracted fonts
            self.cleanFontsDirectory()

            for (id, file) in files.enumerated() {
                let ext = file.name.lowercased()
                if ext.hasSuffix(".mkv") || ext.hasSuffix(".webm") {
                    self.fileMap[hash + String(id)] = file.url
                }
            }
        }
    }

    // MARK: - Metadata Access (mirrors web's `_metadata()`)

    /// Gets or creates parsed metadata for a file, mirroring web's `_metadata(hash, id)`:
    ///
    /// ```js
    /// // web: attachments.ts
    /// _metadata(hash, id) {
    ///     const file = this.filemap.get(hash + id)
    ///     if (!file) return
    ///     const meta = this.metadatamap.get(file)
    ///     if (meta) return meta
    ///     const metadata = new Metadata(file)
    ///     this.metadatamap.set(file, metadata)
    ///     return metadata
    /// }
    /// ```
    private func metadata(hash: String, id: Int) -> MatroskaSubtitles? {
        let key = hash + String(id)

        // Use a barrier write to prevent duplicate parsing when multiple
        // threads request metadata for the same file simultaneously.
        return queue.sync(flags: .barrier) {
            guard let fileURL = fileMap[key] else { return nil }

            if let cached = metadataMap[fileURL] {
                return cached
            }

            // Parse the MKV file on disk using MatroskaSubtitleParser
            let parser = MatroskaSubtitleParser()
            guard let result = try? parser.parse(fileAt: fileURL) else { return nil }

            metadataMap[fileURL] = result
            return result
        }
    }

    // MARK: - Attachments (mirrors web's `attachments.attachments()`)

    /// Extracts embedded file attachments (fonts, images) from the MKV container.
    ///
    /// The web version serves attachments over HTTP and returns URLs:
    /// ```js
    /// // web: attachments.ts
    /// async attachments(hash, id) {
    ///     const metadata = this._metadata(hash, id)
    ///     return (await metadata.getAttachments()).map(({ filename, mimetype }, number) => {
    ///         return { filename, mimetype, id, url: 'http://localhost:...' }
    ///     })
    /// }
    /// ```
    ///
    /// The iOS version writes fonts to disk so MPV can read them via `--sub-fonts-dir`.
    /// Returns attachment metadata for UI display.
    func attachments(hash: String, id: Int) -> [MKVAttachment] {
        guard let meta = metadata(hash: hash, id: id) else { return [] }

        return meta.files.enumerated().compactMap { (number, file) in
            guard let data = file.data else { return nil }
            let filename = file.filename ?? "attachment_\(number)"
            let mimetype = file.mimetype ?? "application/octet-stream"

            return MKVAttachment(
                filename: filename,
                mimetype: mimetype,
                id: number,
                data: data
            )
        }
    }

    /// Extracts font attachments from the MKV and writes them to the fonts directory.
    /// Call after the MKV header pieces have been downloaded.
    /// Returns the number of fonts extracted.
    @discardableResult
    func extractFonts(hash: String, id: Int) -> Int {
        let attachmentList = attachments(hash: hash, id: id)
        var fontCount = 0

        for attachment in attachmentList {
            if Self.isFontAttachment(filename: attachment.filename, mimetype: attachment.mimetype) {
                let destURL = fontsDirectory.appendingPathComponent(attachment.filename)
                try? attachment.data.write(to: destURL, options: .atomic)
                fontCount += 1
            }
        }

        return fontCount
    }

    // MARK: - Tracks (mirrors web's `attachments.tracks()`)

    /// Returns track metadata from the MKV container, mirroring web's API:
    ///
    /// ```js
    /// // web: attachments.ts
    /// tracks(hash, id) {
    ///     const metadata = this._metadata(hash, id)
    ///     return metadata.getTracks()
    /// }
    /// ```
    func tracks(hash: String, id: Int) -> [MKVTrack] {
        guard let meta = metadata(hash: hash, id: id) else { return [] }

        return meta.tracks.map { track in
            MKVTrack(
                number: String(track.number),
                language: track.language,
                type: track.type,
                header: track.header,
                name: track.name
            )
        }
    }

    // MARK: - Chapters (mirrors web's `attachments.chapters()`)

    /// Returns chapter markers from the MKV container, mirroring web's API:
    ///
    /// ```js
    /// // web: attachments.ts
    /// chapters(hash, id) {
    ///     const metadata = this._metadata(hash, id)
    ///     return metadata.getChapters()
    /// }
    /// ```
    ///
    /// Note: matroska-swift's subtitle parser focuses on subtitle extraction
    /// and does not currently parse the Chapters element. Chapters are instead
    /// read by MPV directly from the container via `chapter-list` property.
    /// This method is provided for API parity with the web version.
    func chapters(hash: String, id: Int) -> [MKVChapter] {
        // The matroska-swift library (MatroskaSubtitleParser) focuses on
        // subtitle tracks and attachments. Chapter parsing is not yet
        // implemented in the library. MPV handles chapter extraction natively
        // via its demuxer, which the iOS app already uses through
        // MPVWrapper.getChapters().
        //
        // When matroska-swift adds chapter support, this method will be
        // updated to use it. For now, return empty to match the API shape.
        return []
    }

    // MARK: - Subtitles (mirrors web's `attachments.subtitle()`)

    /// Streams subtitles via a callback, mirroring web's event-based API:
    ///
    /// ```js
    /// // web: attachments.ts
    /// subtitle(hash, id, cb) {
    ///     const metadata = this._metadata(hash, id)
    ///     metadata.removeAllListeners('subtitle')
    ///     metadata.on('subtitle', (a, b) => cb(a, b))
    /// }
    /// ```
    ///
    /// The iOS version parses already-available data and delivers subtitles
    /// synchronously to the callback.
    func subtitles(hash: String, id: Int,
                   callback: @escaping (MKVSubtitle, Int) -> Void) {
        guard let meta = metadata(hash: hash, id: id) else { return }

        for (trackNumber, subs) in meta.subtitles {
            for sub in subs {
                let subtitle = MKVSubtitle(
                    text: sub.text,
                    time: sub.time,
                    duration: sub.duration
                )
                callback(subtitle, trackNumber)
            }
        }
    }

    // MARK: - Cleanup

    /// Removes all registered files and cached metadata.
    func destroy() {
        queue.async(flags: .barrier) { [weak self] in
            self?.fileMap.removeAll()
            self?.metadataMap.removeAll()
        }
        cleanFontsDirectory()
    }

    private func cleanFontsDirectory() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: fontsDirectory, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? fm.removeItem(at: file)
        }
    }
}
