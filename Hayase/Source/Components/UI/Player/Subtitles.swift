//
//  Subtitles.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/subtitles.ts, the part of it that brings subtitle files to the
//  player: the subtitle files that come with the torrent, the files that subtitle extensions return, and
//  the fonts of the torrent. (What the renderer does with them is MPV's job here, where the interface has
//  JASSUB; the tracks inside the video are read by `VideoPlayerViewController`.)
//
//  The interface fetches each file, turns it into a track (`addSingleSubtitleFile`) and selects it when no
//  track is selected yet. Here a file is fetched too, put in a temporary file for MPV, and added as a track
//  with the title and the language the interface gives it.
//

import UIKit
import Foundation
import AVKit

final class Subtitles {
    /// `subtitleExtensions` of lib/utils.ts
    static let subtitleExtensions = ["srt", "vtt", "ass", "ssa", "sub", "txt"]
    /// `fontExtensions` of lib/utils.ts
    static let fontExtensions = ["ttf", "ttc", "woff", "woff2", "otf", "cff", "otc", "pfa", "pfb", "pcf", "fnt", "bdf", "pfr", "eot"]

    private struct Pending {
        let data: Data
        let name: String
    }

    private weak var mpv: MPVWrapper?
    /// `selected.name`: the file that plays
    private let videoName: String
    private var tasks: [URLSessionDataTask] = []
    private var extensionTask: Task<Void, Never>?
    private var pending: [Pending] = []
    private var fileLoaded = false
    private var destroyed = false
    /// `1000 + Object.keys(this._tracks.value).length`: the number a track of a file has, for its fallback name
    private var added = 0
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HayaseSubtitles", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    init(mpv: MPVWrapper, videoName: String) {
        self.mpv = mpv
        self.videoName = videoName
    }

    deinit {
        destroy()
    }

    // MARK: - Where the files come from

    /// The constructor of `Subtitles`: the files of the torrent that are not the video, and what the subtitle
    /// extensions have for the episode.
    func start(otherFiles: [WebTorrentFile], item: AnimeItem?, episode: Int) {
        // a torrent's subtitle files: one is the one; of several, those named like the video
        let subFiles = otherFiles.filter { Self.matches($0.name, extensions: Self.subtitleExtensions) }
        if subFiles.count == 1 {
            fetchAndLoad(url: subFiles[0].url, name: subFiles[0].name)
        } else if subFiles.count > 1 {
            let dot = videoName.lastIndex(of: ".")
            let stem = dot.map { String(videoName[..<$0]) } ?? videoName
            let base = stem.isEmpty ? videoName : stem
            for file in subFiles where file.name.contains(base) {
                fetchAndLoad(url: file.url, name: file.name)
            }
        }

        // `extensions.subtitlesQuery(media, episode)`
        if let item {
            extensionTask = Task { @MainActor [weak self] in
                let results = await ExtensionService.shared.subtitlesQuery(item: item, episode: episode)
                for result in results {
                    guard let self, !self.destroyed else { return }
                    self.fetchAndLoad(url: result.url, name: result.language)
                }
            }
        }

        // fonts the torrent brings: libass finds them in a folder
        let fonts = otherFiles.filter { Self.matches($0.name, extensions: Self.fontExtensions) }
        if !fonts.isEmpty { loadFonts(fonts, hash: otherFiles.first?.hash ?? "") }
    }

    /// The video is there: the files that came in before can be given to MPV.
    func fileDidLoad() {
        fileLoaded = true
        let waiting = pending
        pending = []
        for file in waiting { add(data: file.data, name: file.name) }
    }

    func destroy() {
        destroyed = true
        tasks.forEach { $0.cancel() }
        tasks = []
        extensionTask?.cancel()
        extensionTask = nil
        pending = []
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - fetchAndLoad

    /// `const res = await fetch(file.url); await this.addSingleSubtitleFile(new File([blob], file.name))`
    private func fetchAndLoad(url: String, name: String) {
        guard !destroyed, let url = URL(string: url) else { return }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let data, !data.isEmpty,
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return }
            DispatchQueue.main.async {
                guard let self, !self.destroyed else { return }
                if self.fileLoaded {
                    self.add(data: data, name: name)
                } else {
                    self.pending.append(Pending(data: data, name: name))
                }
            }
        }
        tasks.append(task)
        task.resume()
    }

    // MARK: - addSingleSubtitleFile

    private func add(data: Data, name: String) {
        guard let mpv else { return }
        // `file.name.lastIndexOf('.')`, and the extension after it; a name with no dot is its own extension
        let dot = name.lastIndex(of: ".")
        let fileExtension = (dot.map { String(name[name.index(after: $0)...]) } ?? name).lowercased()
        guard Self.subtitleExtensions.contains(fileExtension) else { return }
        let filename = dot.map { String(name[..<$0]) } ?? String(name.dropLast())

        // "sub name could contain video name with or without extension, possibly followed by lang, or not."
        let trackName: String
        if filename.contains(videoName) {
            trackName = Self.replacingFirst(videoName, in: filename)
        } else {
            let videoDot = videoName.lastIndex(of: ".")
            let stem = videoDot.map { String(videoName[..<$0]) } ?? String(videoName.dropLast())
            trackName = Self.replacingFirst(stem, in: filename)
        }

        let text = String(decoding: data, as: UTF8.self)
        guard Self.isSubtitleText(text, extension: fileExtension) else { return }

        // `1000 + n`, for a file that has nothing to name it by
        let number = 1000 + added
        let cleaned = trackName.replacingOccurrences(of: "[,._-]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let language = Self.detectCJKLanguage(text) ?? (cleaned.isEmpty ? "Track \(number)" : cleaned)

        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }
        let file = directory.appendingPathComponent("\(added)-\(Self.safeFileName(name))")
        guard (try? data.write(to: file)) != nil else { return }
        added += 1

        // "if (this.current.value === -1) selectCaptions(trackNumber)": a track is selected when none is
        let select = !mpv.hasSelectedSubtitleTrack()
        mpv.addExternalSubtitle(path: file.path, select: select, title: trackName, language: language)
        if select { mpv.setSubtitleDefaultFont(Self.defaultFont(forLanguage: language)) }
    }

    // MARK: - Fonts

    private func loadFonts(_ fonts: [WebTorrentFile], hash: String) {
        let folder = directory.appendingPathComponent("fonts", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return }
        let group = DispatchGroup()
        for font in fonts {
            guard let url = URL(string: font.url) else { continue }
            group.enter()
            let task = URLSession.shared.dataTask(with: url) { data, response, _ in
                defer { group.leave() }
                guard let data, !data.isEmpty,
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return }
                try? data.write(to: folder.appendingPathComponent(Self.safeFileName(font.name)))
            }
            tasks.append(task)
            task.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, !self.destroyed else { return }
            self.mpv?.setSubtitleFontsDirectory(folder.path)
        }
    }

    // MARK: - Helpers

    /// `subRx` / `fontRx`: `new RegExp('.(ext|…)$', 'i')`, where the first dot matches any character
    private static func matches(_ name: String, extensions: [String]) -> Bool {
        let lowered = name.lowercased()
        return extensions.contains { lowered.hasSuffix($0) && lowered.count > $0.count }
    }

    /// JavaScript's `string.replace(search, '')`: the first match only
    private static func replacingFirst(_ search: String, in text: String) -> String {
        guard !search.isEmpty, let range = text.range(of: search) else { return text }
        return text.replacingCharacters(in: range, with: "")
    }

    private static func safeFileName(_ name: String) -> String {
        name.replacingOccurrences(of: "[/\\\\:]", with: "_", options: .regularExpression)
    }

    /// `convertSubText` only answers for text it knows how to read: a file of a known extension always, any
    /// other (`txt`) when its content looks like one of the formats.
    private static func isSubtitleText(_ text: String, extension fileExtension: String) -> Bool {
        if ["ass", "ssa", "srt", "vtt", "sub"].contains(fileExtension) { return true }
        // "subbers have a tendency to not set the extensions at all"
        if text.hasPrefix("[Script Info]") { return true }
        let range = NSRange(text.startIndex..., in: text)
        let srt = #"(?:\d+\r?\n)?(\S{9,12})\s?-->\s?(\S{9,12})(.*)\r?\n([\s\S]*)$"#
        if let regex = try? NSRegularExpression(pattern: srt, options: [.caseInsensitive]),
           regex.firstMatch(in: text, range: range) != nil { return true }
        let sub = #"[{\[](\d+)[}\]][{\[](\d+)[}\]](.+)"#
        if let regex = try? NSRegularExpression(pattern: sub, options: [.caseInsensitive]),
           regex.firstMatch(in: text, range: range) != nil { return true }
        return false
    }

    /// `detectCJKLanguage`: the language of the first 10,000-character chunk that has kana, hangul or hanzi
    private static let japaneseRanges: [ClosedRange<UInt32>] = [0x3040...0x309f, 0x30a0...0x30ff]
    private static let koreanRanges: [ClosedRange<UInt32>] = [0xac00...0xd7af, 0x1100...0x11ff, 0x3130...0x318f, 0xa960...0xa97f, 0xd7b0...0xd7ff]
    private static let chineseRanges: [ClosedRange<UInt32>] = [0x4e00...0x9fff, 0x3400...0x4dbf]

    private static func detectCJKLanguage(_ text: String) -> String? {
        let characters = Array(text.unicodeScalars)
        func has(_ ranges: [ClosedRange<UInt32>], in chunk: ArraySlice<Unicode.Scalar>) -> Bool {
            chunk.contains { scalar in ranges.contains { $0.contains(scalar.value) } }
        }
        var index = 0
        while index < characters.count {
            let chunk = characters[index..<min(index + 10_000, characters.count)]
            if has(japaneseRanges, in: chunk) { return "jpn" }
            if has(koreanRanges, in: chunk) { return "kor" }
            if has(chineseRanges, in: chunk) { return "chi" }
            index += 10_000
        }
        return nil
    }
}

// MARK: - Which track is selected

/// What the selection of tracks looks at of a track: `SubtitleTrack` of the interface
struct SubtitleTrackMeta: Equatable {
    var number: String
    var language: String?
    var name: String?
    var forced: Bool
    var isDefault: Bool
}

extension Subtitles {
    /// `lastSelectedTrack`: the track chosen last, of any episode, which the next episode takes again
    static var lastSelectedTrack: SubtitleTrackMeta?

    /// `LANGUAGE_OVERRIDES`: the font that a track in a CJK language falls back to. The fonts are the ones of the
    /// interface (`AVAILABLE_FONTS`, which JASSUB is given the files of), in `Resources/Fonts` and registered with
    /// the app, so that libass finds them by name.
    private static let languageFonts: [String: String] = [
        "jpn": "Noto Sans JP Bold",
        "kor": "Noto Sans KR Bold",
        "chi": "Noto Sans HK",
        "ja": "Noto Sans JP Bold",
        "ko": "Noto Sans KR Bold",
        "zh": "Noto Sans HK",
    ]

    /// What `selectCaptions` gives `setDefaultFont`: the font of the language, else 'roboto medium'
    static func defaultFont(forLanguage language: String?) -> String {
        language.flatMap { languageFonts[$0] } ?? "roboto medium"
    }

    /// The track that is selected when the tracks of an episode are known (the `native.tracks(...).then` of the
    /// constructor): nothing when the subtitle language is none; the only track there is; the track the last
    /// episode had (same language and name, then number); else among the tracks of the wanted language, or of English,
    /// the one that `selectDesired` finds; else the first. The number of the track, or nil for none.
    static func preferredTrack(in tracks: [SubtitleTrackMeta], audioLanguage: String, subtitleLanguage: String,
                               last: SubtitleTrackMeta? = Subtitles.lastSelectedTrack) -> String? {
        if subtitleLanguage.isEmpty { return nil }   // if lang set to none dont autoselect
        guard let first = tracks.first else { return nil }
        if tracks.count == 1 { return first.number }

        func selectDesired(_ filtered: [SubtitleTrackMeta]) -> String {
            if filtered.count == 1 { return filtered[0].number }
            // forced for the curent audio lang
            return (filtered.first { sameLanguage($0.language, audioLanguage) && $0.forced }
                // non-forced for not the current audio lang
                ?? filtered.first { !sameLanguage($0.language, audioLanguage) && !$0.forced }
                // default
                ?? filtered.first { $0.isDefault }
                ?? filtered[0]).number
        }

        if let last {
            let matchesLast = tracks.filter { sameLanguage($0.language, last.language, whenBothMissing: true) && $0.name == last.name }
            if !matchesLast.isEmpty {
                if matchesLast.count == 1 { return matchesLast[0].number }
                if let sameNumber = matchesLast.first(where: { $0.number == last.number }) { return sameNumber.number }
                return selectDesired(matchesLast)
            }
        }

        let wantedLanguages = tracks.filter { sameLanguage($0.language ?? "eng", subtitleLanguage) }
        if !wantedLanguages.isEmpty { return selectDesired(wantedLanguages) }

        let englishFallback = tracks.filter { sameLanguage($0.language ?? "eng", "eng") }
        if !englishFallback.isEmpty { return selectDesired(englishFallback) }

        return first.number
    }

    /// `checkAudio`: of several audio tracks, the one in the language of the settings, else the Japanese one; nil when
    /// there is no choice to make (one track, or none that is wanted)
    static func preferredAudioTrack(in tracks: [(id: Int, language: String?)], audioLanguage: String) -> Int? {
        guard tracks.count > 1 else { return nil }
        if let preferred = tracks.first(where: { sameLanguage($0.language, audioLanguage) }) { return preferred.id }
        return tracks.first(where: { sameLanguage($0.language, "jpn") })?.id
    }

    /// `language === other`, for the codes of the settings (ISO 639-2) and the ones of a file, which can be ISO 639-1
    /// as well. A track with no language is none of them.
    static func sameLanguage(_ track: String?, _ other: String?, whenBothMissing: Bool = false) -> Bool {
        guard let track, !track.isEmpty, let other, !other.isEmpty else {
            return whenBothMissing && (track ?? "").isEmpty && (other ?? "").isEmpty
        }
        if track == other { return true }
        return iso639to1[track] ?? track == iso639to1[other] ?? other
    }

    /// ISO 639-2/B → ISO 639-1 mapping for languages supported in Settings → Player → Language Settings.
    /// Includes both bibliographic (639-2/B) and terminology (639-2/T) variants
    /// where they differ (e.g. "idn"/"ind" both → "id").
    private static let iso639to1: [String: String] = [
        "eng": "en",  "jpn": "ja",  "chi": "zh",  "zho": "zh",
        "por": "pt",  "spa": "es",  "ger": "de",  "deu": "de",
        "pol": "pl",  "cze": "cs",  "ces": "cs",  "dan": "da",
        "gre": "el",  "ell": "el",  "fin": "fi",  "fre": "fr",
        "fra": "fr",  "hun": "hu",  "ita": "it",  "kor": "ko",
        "dut": "nl",  "nld": "nl",  "nor": "no",  "rum": "ro",
        "ron": "ro",  "rus": "ru",  "slo": "sk",  "slk": "sk",
        "swe": "sv",  "ara": "ar",  "idn": "id",  "ind": "id",
        "heb": "he",  "vie": "vi",  "tha": "th",  "tur": "tr",
        "hin": "hi",  "ben": "bn",  "per": "fa",  "fas": "fa",
        "mal": "ml",
    ]
}

// MARK: - The player's side of subtitles.ts (the tracks inside the video and which of them is chosen)

extension VideoPlayerViewController {
    /// Returns a `file://` URL for the current MKV on disk (if available)
    /// so `matroska-swift` can parse subtitle track languages directly from
    /// the container header. Returns `nil` for non-file or unknown paths.
    func mkvFileURLForLanguageParsing() -> URL? {
        guard let path = videoEntity?.videoPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard ext == "mkv" || ext == "webm" else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return url
    }

    func makeTrack(from dict: [String: Any], type: String) -> MPVTrack? {
        guard let id = dict["id"] as? Int else { return nil }
        return MPVTrack(id: id,
                        type: type,
                        title: dict["title"] as? String,
                        lang: dict["lang"] as? String,
                        isSelected: dict["selected"] as? Bool ?? false,
                        isForced: dict["forced"] as? Bool ?? false,
                        isDefault: dict["default"] as? Bool ?? false)
    }

    func readTracks(from renderer: MPVWrapper, includeMkvLanguages: Bool = false) -> [MPVTrack] {
        let mkvURL = includeMkvLanguages ? mkvFileURLForLanguageParsing() : nil
        var result: [MPVTrack] = []

        for dict in renderer.getSubtitleTracks(mkvFileURL: mkvURL) {
            if let track = makeTrack(from: dict, type: "sub") {
                result.append(track)
            }
        }
        for dict in renderer.getAudioTracks() {
            if let track = makeTrack(from: dict, type: "audio") {
                result.append(track)
            }
        }
        for dict in renderer.getVideoTracks() {
            if let track = makeTrack(from: dict, type: "video") {
                result.append(track)
            }
        }

        return result
    }

    func mergeCachedTrackMetadata(into freshTracks: [MPVTrack]) -> [MPVTrack] {
        guard !tracks.isEmpty else { return freshTracks }
        let cachedByKey = Dictionary(tracks.map { (trackKey($0), $0) }, uniquingKeysWith: { first, _ in first })

        return freshTracks.map { fresh in
            guard let cached = cachedByKey[trackKey(fresh)] else { return fresh }
            return MPVTrack(id: fresh.id,
                            type: fresh.type,
                            title: fresh.title ?? cached.title,
                            lang: fresh.lang ?? cached.lang,
                            isSelected: fresh.isSelected,
                            isForced: fresh.isForced,
                            isDefault: fresh.isDefault)
        }
    }

    func currentTracksForOptions() -> [MPVTrack] {
        let freshTracks = readTracks(from: surface.mpv)
        guard !freshTracks.isEmpty else { return tracks }
        return mergeCachedTrackMetadata(into: freshTracks)
    }

    func trackKey(_ track: MPVTrack) -> String {
        "\(track.type):\(track.id)"
    }

    /// Selects the audio and subtitle tracks that the language settings, the forced and default flags and the
    /// track of the last episode ask for (`checkAudio` of player.svelte and `Subtitles` of subtitles.ts).
    func applyPreferredLanguages(renderer: MPVWrapper, tracks: [MPVTrack]) {
        // `checkAudio` of player.svelte: of several audio tracks the one in the language of the settings, else the Japanese one
        let audio = tracks.filter { $0.type == "audio" }.map { (id: $0.id, language: $0.lang) }
        if let id = Subtitles.preferredAudioTrack(in: audio, audioLanguage: Settings.audioLanguage) {
            renderer.setAudioTrack(id)
        }

        // the tracks of `Subtitles`: none when the subtitle language is none, else the one the settings and the
        // last episode ask for
        let subtitleTracks = tracks.filter { $0.type == "sub" }
        let metas = subtitleTracks.map {
            SubtitleTrackMeta(number: String($0.id), language: $0.lang, name: $0.title, forced: $0.isForced, isDefault: $0.isDefault)
        }
        if let number = Subtitles.preferredTrack(in: metas, audioLanguage: Settings.audioLanguage,
                                                 subtitleLanguage: Settings.subtitleLanguage),
           let id = Int(number), let track = subtitleTracks.first(where: { $0.id == id }) {
            if track.isSelected {
                Subtitles.lastSelectedTrack = metas.first { $0.number == number }
            } else {
                selectSubtitleTrack(id, in: subtitleTracks)
            }
        } else if Settings.subtitleLanguage.isEmpty, subtitleTracks.contains(where: { $0.isSelected }) {
            // "None" selected in settings → disable subtitles
            renderer.disableSubtitles()
        }
    }

    /// `selectCaptions`: the track is selected, and it is the one that the next episode looks for
    func selectSubtitleTrack(_ id: Int, in tracks: [MPVTrack]? = nil) {
        surface.mpv.setSubtitleTrack(id)
        guard id >= 0,
              let track = (tracks ?? self.tracks).first(where: { $0.type == "sub" && $0.id == id }) else { return }
        surface.mpv.setSubtitleDefaultFont(Subtitles.defaultFont(forLanguage: track.lang))
        Subtitles.lastSelectedTrack = SubtitleTrackMeta(number: String(id), language: track.lang, name: track.title,
                                                        forced: track.isForced, isDefault: track.isDefault)
    }
}
