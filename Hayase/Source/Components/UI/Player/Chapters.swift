//
//  Chapters.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/chapters.ts: the chapters of an episode as the player works with them.
//  The chapters of the file are made whole (a chapter for every part of the episode), and the ones that
//  are an opening, an ending, a recap and the like are marked as skippable. When the file has no chapters to
//  read, AniSkip has them for the episode. An opening or an ending that is on its first episode is not
//  skipped by itself, which AnimeThemes says.
//

import UIKit
import Foundation

// MARK: - Chapter

/// `Chapter` of chapters.ts, in seconds.
struct Chapter: Equatable {
    var start: Double
    var end: Double
    var text: String
    var skippable = false
    var autoskippable = false
    var skiptype: String?

    /// `chapterLength`
    var length: Double { end - start }
}

/// A chapter as a file or AniSkip tells it, in milliseconds.
struct RawChapter {
    var start: Double
    var end: Double
    var text: String
}

// MARK: - Chapters

final class Chapters {
    /// `SKIPPABLE_CHAPTER_RX_MAP`, in its order; a chapter that matches several gets the last of them
    private static let skippableChapterPatterns: [(type: String, pattern: String)] = [
        ("Opening", #"^op(?:$|[ :\d])|opening$|^opening[ :\d]|^ncop"#),
        ("Ending", #"^ed(?:$|[ :\d])|ending$|^ending[ :\d]|^nced"#),
        ("Intro", #"^intro$"#),
        ("Outro", #"^outro$"#),
        ("Credits", #"^credits$"#),
        ("Preview", #"^preview$"#),
        ("Recap", #"recap"#),
    ]

    /// `AUTO_SKIPPABLE_CHAPTERS_ORDER`
    private static let autoSkippableOpeningTypes = ["Opening", "Intro"]
    private static let autoSkippableEndingTypes = ["Ending", "Outro", "Credits"]

    private let episode: Int
    /// `isFirstOccurence`: asked for when the player is made, as the interface does
    private let firstOccurrence: Task<(op: Bool, ed: Bool), Never>

    init(mediaID: Int, episode: Int) {
        self.episode = episode
        firstOccurrence = Task { await Self.getFirstOccurrences(mediaID: mediaID, episode: episode) }
    }

    deinit {
        firstOccurrence.cancel()
    }

    // MARK: - loadChapters

    /// `loadChapters`: the chapters of the file when it has them, else AniSkip's when the file is one that
    /// has no chapters to read (the interface reads them from Matroska files only; there AniSkip is for
    /// whatever the file does not give). Empty when there are none.
    func loadChapters(fileChapters: [RawChapter], malID: Int?, readsChaptersOfContainer: Bool, duration: Double) async -> [Chapter] {
        guard duration > 0 else { return [] }
        if !fileChapters.isEmpty {
            return await processChapters(Self.sanitizeChapters(fileChapters, length: duration))
        }
        guard !readsChaptersOfContainer, let malID else { return [] }
        let aniSkip = await Self.getChaptersAniSkip(malID: malID, episode: episode, duration: duration)
        guard !aniSkip.isEmpty else { return [] }
        return await processChapters(Self.sanitizeChapters(aniSkip, length: duration))
    }

    // MARK: - getFirstOccurences

    /// "if an opening shows up for the first time for this episode, we dont want to skip!"
    private static func getFirstOccurrences(mediaID: Int, episode: Int) async -> (op: Bool, ed: Bool) {
        let response: AnimeThemesResponse? = await withCheckedContinuation { continuation in
            AnimeThemesService.shared.themes(anilistID: mediaID) { continuation.resume(returning: $0) }
        }
        guard response?.anime?.first?.animethemes != nil else { return (op: episode == 1, ed: episode == 1) }
        var occurrences = (op: false, ed: false)
        for anime in response?.anime ?? [] {
            for theme in anime.animethemes ?? [] {
                for entry in theme.animethemeentries ?? [] {
                    guard let episodes = entry.episodes, !episodes.isEmpty else { continue }
                    let first = episodes.split(separator: "-", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    // `parseInt(first) === episode`
                    guard let number = parseInt(first), number == episode else { continue }
                    if theme.type == "OP" {
                        occurrences.op = true
                    } else if theme.type == "ED" {
                        occurrences.ed = true
                    }
                }
            }
        }
        return occurrences
    }

    /// JavaScript's `parseInt`: the digits a string starts with
    private static func parseInt(_ text: String) -> Int? {
        let trimmed = text.drop(while: { $0 == " " })
        var digits = ""
        for (offset, character) in trimmed.enumerated() {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else if offset == 0, character == "-" || character == "+" {
                digits.append(character)
            } else {
                break
            }
        }
        return Int(digits)
    }

    // MARK: - processChapters

    func processChapters(_ input: [Chapter]) async -> [Chapter] {
        var chapters = input
        guard !chapters.isEmpty else { return chapters }

        for (skiptype, pattern) in Self.skippableChapterPatterns {
            for index in chapters.indices where Self.matches(pattern, chapters[index].text) {
                chapters[index].skiptype = skiptype
                chapters[index].skippable = true
            }
        }

        let (op, ed) = await firstOccurrence.value
        if op && ed { return chapters }

        // iterate in order of importance, if a chapter is skippable, mark it as autoskippable but make sure to
        // only mark one chapter as autoskippable if there are multiple of the same type
        var toSkip: [String] = []
        if !ed { toSkip.append(contentsOf: Self.autoSkippableEndingTypes) }
        if !op { toSkip.append(contentsOf: Self.autoSkippableOpeningTypes) }
        for type in toSkip {
            guard let pattern = Self.skippableChapterPatterns.first(where: { $0.type == type })?.pattern else { continue }
            for index in chapters.indices {
                guard chapters[index].skippable else { continue }
                let length = chapters[index].length
                if length < 60 || length > 120 { continue }
                if Self.matches(pattern, chapters[index].text) {
                    chapters[index].autoskippable = true
                    break
                }
            }
        }
        return chapters
    }

    /// `regex.test(text)` of a pattern with the flags `mi`
    private static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - findChapter and getChapterTitle

    /// `findChapter`
    static func find(_ time: Double, in chapters: [Chapter]) -> Chapter? {
        chapters.first { time >= $0.start && time <= $0.end }
    }

    // MARK: - sanitizeChapters

    /// `sanitizeChapters`: chapters within the episode, with a chapter for every part of it
    static func sanitizeChapters(_ chapters: [RawChapter], length: Double) -> [Chapter] {
        if length <= 0 { return [] }

        var sanitized: [Chapter] = []
        var currentTime = 0.0

        let sorted = chapters.map { chapter -> Chapter in
            let end = max(0, min(length, chapter.end / 1000))
            let start = min(max(0, chapter.start / 1000), end)
            return Chapter(start: start, end: end, text: chapter.text)
        }.enumerated().sorted { lhs, rhs in
            lhs.element.start != rhs.element.start ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
        }.map(\.element)

        for chapter in sorted {
            // Handle Missing Segment Before Chapter
            if chapter.start > currentTime {
                sanitized.append(Chapter(start: currentTime, end: chapter.start, text: sanitized.isEmpty ? "" : "Episode"))
            }
            sanitized.append(chapter)
            currentTime = chapter.end
        }

        // Handle Missing Segment After Last Chapter
        if currentTime < length {
            sanitized.append(Chapter(start: currentTime, end: length, text: ""))
        }
        return sanitized
    }

    // MARK: - getChaptersAniSkip

    /// `getChaptersAniSkip`: the opening, the ending and the recap of an episode, as chapters in milliseconds
    static func getChaptersAniSkip(malID: Int, episode: Int, duration: Double) async -> [RawChapter] {
        // `episodeLength=${duration}`: a number as JavaScript prints it
        let accurateLength = duration == duration.rounded() ? String(Int(duration)) : String(duration)
        let accurate = await skipTimes(malID: malID, episode: episode, episodeLength: accurateLength)
        let rough = await skipTimes(malID: malID, episode: episode, episodeLength: "0")

        // the first result of each type wins, the accurate ones before the rough ones
        var results: [[String: Any]] = []
        var seen = Set<String>()
        for result in accurate + rough {
            guard let type = result["skipType"] as? String, seen.insert(type).inserted else { continue }
            results.append(result)
        }
        guard !results.isEmpty else { return [] }

        var chapters: [RawChapter] = results.compactMap { result in
            guard let interval = result["interval"] as? [String: Any],
                  let startTime = (interval["startTime"] as? NSNumber)?.doubleValue,
                  let endTime = (interval["endTime"] as? NSNumber)?.doubleValue,
                  let type = result["skipType"] as? String else { return nil }
            let diff = duration - ((result["episodeLength"] as? NSNumber)?.doubleValue ?? 0)
            return RawChapter(start: max(0, (startTime + diff) * 1000),
                              end: min(duration * 1000, max(0, (endTime + diff) * 1000)),
                              text: type.uppercased())
        }
        let edEnd = chapters.first { $0.text == "ED" }?.end
        if let recap = chapters.firstIndex(where: { $0.text == "RECAP" }) { chapters[recap].text = "Recap" }

        guard !chapters.isEmpty else { return [] }
        chapters = chapters.enumerated().sorted { lhs, rhs in
            lhs.element.start != rhs.element.start ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
        }.map(\.element)
        // `x | 0`
        func truncated(_ value: Double) -> Double { Double(Int(safe: value)) }
        if Int(safe: chapters[0].start) != 0 {
            chapters.insert(RawChapter(start: 0, end: chapters[0].start, text: chapters[0].text == "OP" ? "Intro" : "Episode"), at: 0)
        }
        if let edEnd {
            if truncated(edEnd) + 5000 - duration * 1000 < 0 {
                chapters.append(RawChapter(start: edEnd, end: duration * 1000, text: "Preview"))
            }
        } else if let last = chapters.last, truncated(last.end) + 5000 - duration * 1000 < 0 {
            chapters.append(RawChapter(start: last.end, end: duration * 1000, text: "Episode"))
        }

        // a chapter for what is between two chapters
        let snapshot = chapters
        if snapshot.count > 1 {
            for index in 0..<(snapshot.count - 1) where Int(safe: snapshot[index].end) != Int(safe: snapshot[index + 1].start) {
                chapters.append(RawChapter(start: snapshot[index].end, end: snapshot[index + 1].start, text: "Episode"))
            }
        }

        return chapters.enumerated().sorted { lhs, rhs in
            lhs.element.start != rhs.element.start ? lhs.element.start < rhs.element.start : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func skipTimes(malID: Int, episode: Int, episodeLength: String) async -> [[String: Any]] {
        guard let url = URL(string: "https://api.aniskip.com/v2/skip-times/\(malID)/\(episode)/?episodeLength=\(episodeLength)&types=op&types=ed&types=recap"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results
    }
}

// MARK: - The player's side of chapters.ts (the markers, the title and the skip button)

extension VideoPlayerViewController {
    func updateChapterMarkers() {
        seekBar.setChapters(chapters, duration: duration)
    }

    func chapterWindow(at time: Double) -> (title: String, start: Double, end: Double)? {
        guard duration > 0, !chapters.isEmpty else { return nil }
        let sorted = chapters.sorted { $0.time < $1.time }
        for (index, chapter) in sorted.enumerated() {
            let start = max(0, chapter.time)
            let end = index + 1 < sorted.count ? sorted[index + 1].time : duration
            if time >= start && time <= end {
                return (chapter.title, start, min(duration, max(start, end)))
            }
        }
        return nil
    }

    func chapterTitle(at time: Double) -> String {
        (chapterWindow(at: time)?.title ?? "").capitalized
    }

    /// `loadChapters`: the chapters of the file (or, when it has none to read, AniSkip's) made whole, with
    /// what is skippable marked. They replace the file's own once they are there.
    func loadChapters() {
        guard duration > 0, let handler = chaptersHandler else { return }
        chaptersLoadedDuration = duration
        let duration = self.duration
        // the chapters of the file know where they start; one ends where the next starts
        let sorted = fileChapters.sorted { $0.time < $1.time }
        let raw = sorted.enumerated().map { index, chapter in
            RawChapter(start: chapter.time * 1000,
                       end: (index + 1 < sorted.count ? sorted[index + 1].time : duration) * 1000,
                       text: chapter.title)
        }
        let malID = videoService?.media?.malId ?? Router.shared.cachedAnimeItem(for: currentMediaID)?.malId
        let fileExtension = ((videoEntity?.videoName ?? "") as NSString).pathExtension.lowercased()
        chaptersTask?.cancel()
        chaptersTask = Task { @MainActor [weak self] in
            let loaded = await handler.loadChapters(fileChapters: raw, malID: malID,
                                                    readsChaptersOfContainer: ["mkv", "webm"].contains(fileExtension),
                                                    duration: duration)
            guard let self, !Task.isCancelled, self.chaptersHandler === handler, !loaded.isEmpty else { return }
            self.chapterModel = loaded
            self.chapters = loaded.enumerated().map { MPVChapter(index: $0.offset, title: $0.element.text, time: $0.element.start) }
            self.updateChapterMarkers()
            self.updateSkipChapterButton()
        }
    }

    /// `checkSkippableChapters`
    func updateSkipChapterButton() {
        guard let current = Chapters.find(currentTime, in: chapterModel) else { return }
        let next = current.skippable ? current : nil
        guard next != currentSkippableChapter else { return }
        let wasAutoskippable = currentSkippableChapter?.autoskippable ?? false
        currentSkippableChapter = next
        if let next {
            skipChapterButton.setTitle("Skip \(next.skiptype ?? "")")
            skipChapterButton.stopProgress()
            let w2gAllowsSkip = W2GLobby.shared.client.map { $0.peers.count > 1 } ?? true
            // an opening or ending that is not on its first episode skips by itself, after the button has run
            if Settings.playerSkip, next.autoskippable, !wasAutoskippable, w2gAllowsSkip {
                skipChapterButton.startProgress(duration: 3)
            }
        } else {
            skipChapterButton.stopProgress()
        }
        updateInterfaceOverlayVisibility(animated: true)
    }

    /// `skip()`: past the chapter, 85 seconds on in a long one that is not skippable, or where 90 seconds /
    /// the end of the episode is when there is no chapter.
    func skipCurrentChapter() {
        guard duration > 0 else { return }
        let target: Double
        if let current = Chapters.find(currentTime, in: chapterModel) {
            if !current.skippable && current.length > 100 {
                target = currentTime + 85
            } else {
                target = current.end + 0.5
                currentSkippableChapter = nil
            }
        } else if currentTime < 10 {
            target = 90
        } else if duration - currentTime < 90 {
            target = duration
        } else {
            target = currentTime + 85
        }
        let targetTime = min(duration, target)
        surface.mpv.seek(to: targetTime)
        lastSeekTime = Date()
        isSeeking = true
        pendingSeekDisplayTime = targetTime
        currentSkippableChapter = nil
        skipChapterButton.stopProgress()
        renderSeekTargetUI(time: targetTime)
        updateInterfaceOverlayVisibility(animated: true)
        scheduleHide()

        doubleTapSeekRestoreWork?.cancel()
        let restoreWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.doubleTapSeekRestoreWork = nil
            self.isSeeking = false
            self.pendingSeekDisplayTime = nil
            self.updateTimeUI()
        }
        doubleTapSeekRestoreWork = restoreWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: restoreWork)
    }
}
