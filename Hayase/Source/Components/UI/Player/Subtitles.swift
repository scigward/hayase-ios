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

import Foundation

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
        mpv.addExternalSubtitle(path: file.path, select: !mpv.hasSelectedSubtitleTrack(),
                                title: trackName, language: language)
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
