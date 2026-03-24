//
//  Anitomy.swift
//  Hayase
//
//  A faithful Swift port of erengy/anitomy – a C++ library for parsing
//  anime video filenames. Licensed under MPL 2.0.
//
//  Original C++ source: https://github.com/erengy/anitomy
//  Copyright (c) 2014-2018 Eren Okka (MPL 2.0)
//

import Foundation

// MARK: - Element

enum ElementCategory: Int, CaseIterable {
    case animeSeason
    case animeSeasonPrefix
    case animeTitle
    case animeType
    case animeYear
    case audioTerm
    case deviceCompatibility
    case episodeNumber
    case episodeNumberAlt
    case episodePrefix
    case episodeTitle
    case fileChecksum
    case fileExtension
    case fileName
    case language
    case other
    case releaseGroup
    case releaseInformation
    case releaseVersion
    case source
    case subtitles
    case videoResolution
    case videoTerm
    case volumeNumber
    case volumePrefix
    case unknown
}

final class AnitomyElements {
    private var elements: [(ElementCategory, String)] = []

    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }

    func get(_ category: ElementCategory) -> String {
        elements.first(where: { $0.0 == category })?.1 ?? ""
    }

    func getAll(_ category: ElementCategory) -> [String] {
        elements.filter { $0.0 == category }.map { $0.1 }
    }

    func isEmpty(_ category: ElementCategory) -> Bool {
        !elements.contains(where: { $0.0 == category })
    }

    func count(_ category: ElementCategory) -> Int {
        elements.filter { $0.0 == category }.count
    }

    func insert(_ category: ElementCategory, _ value: String) {
        guard !value.isEmpty else { return }
        elements.append((category, value))
    }

    func erase(_ category: ElementCategory) {
        elements.removeAll(where: { $0.0 == category })
    }

    func set(_ category: ElementCategory, _ value: String) {
        if let idx = elements.firstIndex(where: { $0.0 == category }) {
            elements[idx] = (category, value)
        } else {
            elements.append((category, value))
        }
    }

    func clear() { elements.removeAll() }

    // Mutable iteration support
    var pairs: [(ElementCategory, String)] { elements }

    func setCategoryAt(index: Int, _ category: ElementCategory) {
        guard index < elements.count else { return }
        elements[index].0 = category
    }

    func eraseAt(index: Int) {
        guard index < elements.count else { return }
        elements.remove(at: index)
    }
}

// MARK: - Token

enum TokenCategory {
    case unknown
    case bracket
    case delimiter
    case identifier
    case invalid
}

struct TokenFlag: OptionSet {
    let rawValue: UInt32
    static let none              = TokenFlag([])
    static let flagBracket       = TokenFlag(rawValue: 1 << 0)
    static let flagNotBracket    = TokenFlag(rawValue: 1 << 1)
    static let flagDelimiter     = TokenFlag(rawValue: 1 << 2)
    static let flagNotDelimiter  = TokenFlag(rawValue: 1 << 3)
    static let flagIdentifier    = TokenFlag(rawValue: 1 << 4)
    static let flagNotIdentifier = TokenFlag(rawValue: 1 << 5)
    static let flagUnknown       = TokenFlag(rawValue: 1 << 6)
    static let flagNotUnknown    = TokenFlag(rawValue: 1 << 7)
    static let flagValid         = TokenFlag(rawValue: 1 << 8)
    static let flagNotValid      = TokenFlag(rawValue: 1 << 9)
    static let flagEnclosed      = TokenFlag(rawValue: 1 << 10)
    static let flagNotEnclosed   = TokenFlag(rawValue: 1 << 11)

    static let maskCategories: TokenFlag = [
        .flagBracket, .flagNotBracket,
        .flagDelimiter, .flagNotDelimiter,
        .flagIdentifier, .flagNotIdentifier,
        .flagUnknown, .flagNotUnknown,
        .flagValid, .flagNotValid
    ]
    static let maskEnclosed: TokenFlag = [.flagEnclosed, .flagNotEnclosed]
}

struct TokenRange {
    var offset: Int = 0
    var size: Int = 0
}

final class AnitomyToken {
    var category: TokenCategory
    var content: String
    var enclosed: Bool

    init(category: TokenCategory = .unknown, content: String = "", enclosed: Bool = false) {
        self.category = category
        self.content = content
        self.enclosed = enclosed
    }
}

// MARK: - Token search helpers

private func checkTokenFlags(_ token: AnitomyToken, _ flags: TokenFlag) -> Bool {
    if !flags.intersection(.maskEnclosed).isEmpty {
        let success = flags.contains(.flagEnclosed) ? token.enclosed : !token.enclosed
        if !success { return false }
    }
    if !flags.intersection(.maskCategories).isEmpty {
        var success = false
        func checkCat(_ fe: TokenFlag, _ fn: TokenFlag, _ c: TokenCategory) {
            if !success {
                if flags.contains(fe) { success = (token.category == c) }
                else if flags.contains(fn) { success = (token.category != c) }
            }
        }
        checkCat(.flagBracket, .flagNotBracket, .bracket)
        checkCat(.flagDelimiter, .flagNotDelimiter, .delimiter)
        checkCat(.flagIdentifier, .flagNotIdentifier, .identifier)
        checkCat(.flagUnknown, .flagNotUnknown, .unknown)
        checkCat(.flagNotValid, .flagValid, .invalid)
        if !success { return false }
    }
    return true
}

private func findToken(in tokens: [AnitomyToken], from start: Int, to end: Int, flags: TokenFlag) -> Int? {
    for i in start..<end {
        if checkTokenFlags(tokens[i], flags) { return i }
    }
    return nil
}

private func findPreviousToken(in tokens: [AnitomyToken], before index: Int, flags: TokenFlag) -> Int? {
    guard index > 0 else { return nil }
    for i in stride(from: index - 1, through: 0, by: -1) {
        if checkTokenFlags(tokens[i], flags) { return i }
    }
    return nil
}

private func findNextToken(in tokens: [AnitomyToken], after index: Int, flags: TokenFlag) -> Int? {
    guard index + 1 < tokens.count else { return nil }
    for i in (index + 1)..<tokens.count {
        if checkTokenFlags(tokens[i], flags) { return i }
    }
    return nil
}

// MARK: - String Utilities

private func isAlphanumericChar(_ c: Character) -> Bool {
    (c >= "0" && c <= "9") || (c >= "A" && c <= "Z") || (c >= "a" && c <= "z")
}

private func isNumericChar(_ c: Character) -> Bool {
    c >= "0" && c <= "9"
}

private func isHexChar(_ c: Character) -> Bool {
    (c >= "0" && c <= "9") || (c >= "A" && c <= "F") || (c >= "a" && c <= "f")
}

private func isLatinChar(_ c: Character) -> Bool {
    guard let scalar = c.unicodeScalars.first else { return false }
    return scalar.value <= 0x024F
}

private func isNumericString(_ str: String) -> Bool {
    !str.isEmpty && str.allSatisfy { isNumericChar($0) }
}

private func isAlphanumericString(_ str: String) -> Bool {
    !str.isEmpty && str.allSatisfy { isAlphanumericChar($0) }
}

private func isHexadecimalString(_ str: String) -> Bool {
    !str.isEmpty && str.allSatisfy { isHexChar($0) }
}

private func isMostlyLatinString(_ str: String) -> Bool {
    let length = max(Double(str.count), 1.0)
    let latinCount = str.filter { isLatinChar($0) }.count
    return Double(latinCount) / length >= 0.5
}

private func stringToInt(_ str: String) -> Int {
    Int(str) ?? 0
}

private func isStringEqualTo(_ s1: String, _ s2: String) -> Bool {
    s1.caseInsensitiveCompare(s2) == .orderedSame
}

private func trimString(_ str: inout String, _ chars: String = " ") {
    let charSet = CharacterSet(charactersIn: chars)
    str = str.trimmingCharacters(in: charSet)
}

// MARK: - Keyword

struct KeywordOptions {
    var identifiable: Bool = true
    var searchable: Bool = true
    var valid: Bool = true
}

struct Keyword {
    var category: ElementCategory
    var options: KeywordOptions
}

final class KeywordManager {
    static let shared = KeywordManager()

    private var fileExtensions: [String: Keyword] = [:]
    private var keys: [String: Keyword] = [:]

    init() {
        let optDefault = KeywordOptions()
        let optInvalid = KeywordOptions(identifiable: true, searchable: true, valid: false)
        let optUnidentifiable = KeywordOptions(identifiable: false, searchable: true, valid: true)
        let optUnidentifiableInvalid = KeywordOptions(identifiable: false, searchable: true, valid: false)
        let optUnidentifiableUnsearchable = KeywordOptions(identifiable: false, searchable: false, valid: true)

        add(.animeSeasonPrefix, optUnidentifiable, ["SAISON", "SEASON"])

        add(.animeType, optUnidentifiable,
            ["GEKIJOUBAN", "MOVIE", "OAD", "OAV", "ONA", "OVA", "SPECIAL", "SPECIALS", "TV"])
        add(.animeType, optUnidentifiableUnsearchable, ["SP"])
        add(.animeType, optUnidentifiableInvalid,
            ["ED", "ENDING", "NCED", "NCOP", "OP", "OPENING", "PREVIEW", "PV"])

        add(.audioTerm, optDefault, [
            "2.0CH", "2CH", "5.1", "5.1CH", "7.1", "7.1CH", "DTS", "DTS-ES", "DTS5.1",
            "DOLBY TRUEHD", "TRUEHD", "TRUEHD5.1",
            "AAC", "AACX2", "AACX3", "AACX4", "AC3", "EAC3", "E-AC-3",
            "FLAC", "FLACX2", "FLACX3", "FLACX4", "LOSSLESS", "MP3", "OGG",
            "VORBIS", "ATMOS", "DOLBY ATMOS",
            "DUALAUDIO", "DUAL AUDIO"])
        add(.audioTerm, optUnidentifiable, ["OPUS"])

        add(.deviceCompatibility, optDefault,
            ["IPAD3", "IPHONE5", "IPOD", "PS3", "XBOX", "XBOX360"])
        add(.deviceCompatibility, optUnidentifiable, ["ANDROID"])

        add(.episodePrefix, optDefault,
            ["EP", "EP.", "EPS", "EPS.", "EPISODE", "EPISODE.", "EPISODES",
             "CAPITULO", "EPISODIO", "EPIS\u{00F3}DIO", "FOLGE"])
        add(.episodePrefix, optInvalid, ["E", "\u{7B2C}"])

        add(.fileExtension, optDefault,
            ["3GP", "AVI", "DIVX", "FLV", "M2TS", "MKV", "MOV", "MP4", "MPG",
             "OGM", "RM", "RMVB", "TS", "WEBM", "WMV"])
        add(.fileExtension, optInvalid,
            ["AAC", "AIFF", "FLAC", "M4A", "MP3", "MKA", "OGG", "WAV", "WMA",
             "7Z", "RAR", "ZIP", "ASS", "SRT"])

        add(.language, optDefault,
            ["ENG", "ENGLISH", "ESPANOL", "JAP", "PT-BR", "SPANISH", "VOSTFR"])
        add(.language, optUnidentifiable, ["ESP", "ITA"])

        add(.other, optDefault,
            ["REMASTER", "REMASTERED", "UNCENSORED", "UNCUT",
             "TS", "VFR", "WIDESCREEN", "WS"])

        add(.releaseGroup, optDefault, ["THORA"])

        add(.releaseInformation, optDefault, ["BATCH", "COMPLETE", "PATCH", "REMUX"])
        add(.releaseInformation, optUnidentifiable, ["END", "FINAL"])

        add(.releaseVersion, optDefault, ["V0", "V1", "V2", "V3", "V4"])

        add(.source, optDefault, [
            "BD", "BDRIP", "BLURAY", "BLU-RAY",
            "DVD", "DVD5", "DVD9", "DVD-R2J", "DVDRIP", "DVD-RIP",
            "R2DVD", "R2J", "R2JDVD", "R2JDVDRIP",
            "HDTV", "HDTVRIP", "TVRIP", "TV-RIP",
            "WEBCAST", "WEBRIP"])

        add(.subtitles, optDefault, [
            "ASS", "BIG5", "DUB", "DUBBED", "HARDSUB", "HARDSUBS", "RAW",
            "SOFTSUB", "SOFTSUBS", "SUB", "SUBBED", "SUBTITLED",
            "MULTISUB", "MULTI SUB"])

        add(.videoTerm, optDefault, [
            "23.976FPS", "24FPS", "29.97FPS", "30FPS", "60FPS", "120FPS",
            "8BIT", "8-BIT", "10BIT", "10BITS", "10-BIT", "10-BITS",
            "HI10", "HI10P", "HI444", "HI444P", "HI444PP",
            "HDR", "DV", "DOLBY VISION",
            "H264", "H265", "H.264", "H.265", "X264", "X265", "X.264",
            "AVC", "HEVC", "HEVC2", "DIVX", "DIVX5", "DIVX6", "XVID",
            "AV1",
            "AVI", "RMVB", "WMV", "WMV3", "WMV9",
            "HQ", "LQ",
            "4K", "HD", "SD"])

        add(.volumePrefix, optDefault, ["VOL", "VOL.", "VOLUME"])
    }

    private func add(_ category: ElementCategory, _ options: KeywordOptions, _ keywords: [String]) {
        for keyword in keywords {
            guard !keyword.isEmpty else { continue }
            if category == .fileExtension {
                if fileExtensions[keyword] == nil {
                    fileExtensions[keyword] = Keyword(category: category, options: options)
                }
            } else {
                if keys[keyword] == nil {
                    keys[keyword] = Keyword(category: category, options: options)
                }
            }
        }
    }

    private func container(for category: ElementCategory) -> [String: Keyword] {
        category == .fileExtension ? fileExtensions : keys
    }

    func find(category: ElementCategory, str: String) -> Bool {
        let c = container(for: category)
        if let kw = c[str], kw.category == category { return true }
        return false
    }

    func find(str: String, category: inout ElementCategory, options: inout KeywordOptions) -> Bool {
        let c = container(for: category)
        if let kw = c[str] {
            if category == .unknown {
                category = kw.category
            } else if kw.category != category {
                return false
            }
            options = kw.options
            return true
        }
        return false
    }

    func normalize(_ str: String) -> String {
        str.uppercased()
    }

    /// Pre-identify known multi-word keywords inside a range of the filename.
    func peek(filename: String, range: TokenRange, elements: AnitomyElements, preidentified: inout [TokenRange]) {
        let entries: [(ElementCategory, [String])] = [
            (.audioTerm, ["Dual Audio"]),
            (.videoTerm, ["H264", "H.264", "h264", "h.264"]),
            (.videoResolution, ["480p", "720p", "1080p", "2160p"]),
            (.source, ["Blu-Ray"]),
        ]

        let startIdx = filename.index(filename.startIndex, offsetBy: range.offset)
        let endIdx = filename.index(startIdx, offsetBy: range.size)
        let substring = String(filename[startIdx..<endIdx])

        for entry in entries {
            for keyword in entry.1 {
                if let foundRange = substring.range(of: keyword) {
                    let offset = range.offset + substring.distance(from: substring.startIndex, to: foundRange.lowerBound)
                    elements.insert(entry.0, keyword)
                    preidentified.append(TokenRange(offset: offset, size: keyword.count))
                }
            }
        }
    }
}

// MARK: - Options

struct AnitomyOptions {
    var allowedDelimiters = " _.&+,|"
    var ignoredStrings: [String] = []
    var parseEpisodeNumber = true
    var parseEpisodeTitle = true
    var parseFileExtension = true
    var parseReleaseGroup = true
}

// MARK: - Tokenizer

private final class AnitomyTokenizer {
    private let filename: String
    private let elements: AnitomyElements
    private let options: AnitomyOptions
    private var tokens: [AnitomyToken]

    init(filename: String, elements: AnitomyElements, options: AnitomyOptions, tokens: inout [AnitomyToken]) {
        self.filename = filename
        self.elements = elements
        self.options = options
        self.tokens = tokens
    }

    func tokenize() -> [AnitomyToken] {
        tokens.reserveCapacity(32)
        tokenizeByBrackets()
        return tokens
    }

    private func addToken(_ category: TokenCategory, enclosed: Bool, _ range: TokenRange) {
        let start = filename.index(filename.startIndex, offsetBy: range.offset)
        let end = filename.index(start, offsetBy: range.size)
        let content = String(filename[start..<end])
        tokens.append(AnitomyToken(category: category, content: content, enclosed: enclosed))
    }

    private static let brackets: [(Character, Character)] = [
        ("(", ")"), ("[", "]"), ("{", "}"),
        ("\u{300C}", "\u{300D}"), ("\u{300E}", "\u{300F}"),
        ("\u{3010}", "\u{3011}"), ("\u{FF08}", "\u{FF09}"),
    ]

    private func tokenizeByBrackets() {
        let chars = Array(filename)
        var isBracketOpen = false
        var matchingBracket: Character = "\0"
        var charBegin = 0

        var currentPos = charBegin

        while currentPos <= chars.count && charBegin <= chars.count {
            if !isBracketOpen {
                // Find first opening bracket
                currentPos = chars.count // default: not found
                for i in charBegin..<chars.count {
                    var found = false
                    for bp in Self.brackets {
                        if chars[i] == bp.0 {
                            matchingBracket = bp.1
                            currentPos = i
                            found = true
                            break
                        }
                    }
                    if found { break }
                }
            } else {
                // Find matching close bracket
                currentPos = chars.count
                for i in charBegin..<chars.count {
                    if chars[i] == matchingBracket {
                        currentPos = i
                        break
                    }
                }
            }

            let rangeSize = currentPos - charBegin
            if rangeSize > 0 {
                tokenizeByPreidentified(enclosed: isBracketOpen,
                                        range: TokenRange(offset: charBegin, size: rangeSize))
            }

            if currentPos < chars.count {
                addToken(.bracket, enclosed: true,
                         TokenRange(offset: currentPos, size: 1))
                isBracketOpen = !isBracketOpen
                currentPos += 1
                charBegin = currentPos
            } else {
                break
            }
        }
    }

    private func tokenizeByPreidentified(enclosed: Bool, range: TokenRange) {
        var preidentified: [TokenRange] = []
        KeywordManager.shared.peek(filename: filename, range: range,
                                   elements: elements, preidentified: &preidentified)

        var offset = range.offset
        var subrange = TokenRange(offset: range.offset, size: 0)

        while offset < range.offset + range.size {
            for pid in preidentified {
                if offset == pid.offset {
                    if subrange.size > 0 {
                        tokenizeByDelimiters(enclosed: enclosed, range: subrange)
                    }
                    addToken(.identifier, enclosed: enclosed, pid)
                    subrange.offset = pid.offset + pid.size
                    offset = subrange.offset - 1
                    break
                }
            }
            offset += 1
            subrange.size = offset - subrange.offset
        }

        if subrange.size > 0 {
            tokenizeByDelimiters(enclosed: enclosed, range: subrange)
        }
    }

    private func tokenizeByDelimiters(enclosed: Bool, range: TokenRange) {
        let delimiters = getDelimiters(range: range)

        if delimiters.isEmpty {
            addToken(.unknown, enclosed: enclosed, range)
            return
        }

        let chars = Array(filename)
        var charBegin = range.offset
        let charEnd = range.offset + range.size
        var currentPos = charBegin

        while currentPos <= charEnd {
            // Find next delimiter
            var delimPos = charEnd
            for i in currentPos..<charEnd {
                if delimiters.contains(chars[i]) {
                    delimPos = i
                    break
                }
            }

            let subSize = delimPos - charBegin
            if subSize > 0 {
                addToken(.unknown, enclosed: enclosed,
                         TokenRange(offset: charBegin, size: subSize))
            }

            if delimPos < charEnd {
                addToken(.delimiter, enclosed: enclosed,
                         TokenRange(offset: delimPos, size: 1))
                currentPos = delimPos + 1
                charBegin = currentPos
            } else {
                break
            }
        }

        validateDelimiterTokens()
    }

    private func getDelimiters(range: TokenRange) -> Set<Character> {
        let chars = Array(filename)
        var delimiters = Set<Character>()
        let allowedSet = Set(options.allowedDelimiters)
        for i in range.offset..<(range.offset + range.size) {
            let c = chars[i]
            if !isAlphanumericChar(c) && allowedSet.contains(c) {
                delimiters.insert(c)
            }
        }
        return delimiters
    }

    private func validateDelimiterTokens() {
        let isDelimToken = { (i: Int?) -> Bool in
            guard let i = i, i < self.tokens.count else { return false }
            return self.tokens[i].category == .delimiter
        }
        let isUnknownToken = { (i: Int?) -> Bool in
            guard let i = i, i < self.tokens.count else { return false }
            return self.tokens[i].category == .unknown
        }
        let isSingleCharToken = { (i: Int?) -> Bool in
            guard let i = i, i < self.tokens.count else { return false }
            return self.tokens[i].category == .unknown &&
                   self.tokens[i].content.count == 1 &&
                   self.tokens[i].content.first != "-"
        }

        for idx in 0..<tokens.count {
            guard tokens[idx].category == .delimiter else { continue }
            let delimiter = tokens[idx].content.first!
            let prev = findPreviousToken(in: tokens, before: idx, flags: .flagValid)
            var next = findNextToken(in: tokens, after: idx, flags: .flagValid)

            if delimiter != " " && delimiter != "_" {
                if isSingleCharToken(prev) {
                    tokens[idx].category = .invalid
                    tokens[prev!].content += tokens[idx].content
                    while isUnknownToken(next) {
                        tokens[prev!].content += tokens[next!].content
                        tokens[next!].category = .invalid
                        let nextNext = findNextToken(in: tokens, after: next!, flags: .flagValid)
                        if isDelimToken(nextNext) && tokens[nextNext!].content.first == delimiter {
                            tokens[prev!].content += tokens[nextNext!].content
                            tokens[nextNext!].category = .invalid
                            next = findNextToken(in: tokens, after: nextNext!, flags: .flagValid)
                        } else {
                            next = nextNext
                        }
                    }
                    continue
                }
                if isSingleCharToken(next) {
                    if let p = prev {
                        tokens[p].content += tokens[idx].content
                        tokens[idx].category = .invalid
                        tokens[p].content += tokens[next!].content
                        tokens[next!].category = .invalid
                    }
                    continue
                }
            }

            // Adjacent delimiters
            if isUnknownToken(prev) && isDelimToken(next) {
                let nextDelim = tokens[next!].content.first!
                if delimiter != nextDelim && delimiter != "," {
                    if nextDelim == " " || nextDelim == "_" {
                        if let p = prev {
                            tokens[p].content += tokens[idx].content
                            tokens[idx].category = .invalid
                        }
                    }
                }
            } else if isDelimToken(prev) && isDelimToken(next) {
                let prevDelim = tokens[prev!].content.first!
                let nextDelim = tokens[next!].content.first!
                if prevDelim == nextDelim && prevDelim != delimiter {
                    tokens[idx].category = .unknown
                }
            }

            // Special: & and +
            if delimiter == "&" || delimiter == "+" {
                if isUnknownToken(prev) && isUnknownToken(next) {
                    if isNumericString(tokens[prev!].content) &&
                       isNumericString(tokens[next!].content) {
                        tokens[prev!].content += tokens[idx].content
                        tokens[idx].category = .invalid
                        tokens[prev!].content += tokens[next!].content
                        tokens[next!].category = .invalid
                    }
                }
            }
        }

        tokens.removeAll(where: { $0.category == .invalid })
    }
}

// MARK: - Parser

private final class AnitomyParser {
    private let elements: AnitomyElements
    private let options: AnitomyOptions
    private var tokens: [AnitomyToken]
    private var foundEpisodeKeywords = false

    private let kAnimeYearMin = 1900
    private let kAnimeYearMax = 2050
    private var kEpisodeNumberMax: Int { kAnimeYearMin - 1 }
    private let kVolumeNumberMax = 20

    private let kDashes = "-\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}"
    private let kDashesWithSpace = " -\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}"

    init(elements: AnitomyElements, options: AnitomyOptions, tokens: inout [AnitomyToken]) {
        self.elements = elements
        self.options = options
        self.tokens = tokens
    }

    func parse() -> [AnitomyToken] {
        searchForKeywords()
        searchForIsolatedNumbersGlobal()

        if options.parseEpisodeNumber {
            searchForEpisodeNumber()
        }

        searchForAnimeTitle()

        if options.parseReleaseGroup && elements.isEmpty(.releaseGroup) {
            searchForReleaseGroup()
        }

        if options.parseEpisodeTitle && !elements.isEmpty(.episodeNumber) {
            searchForEpisodeTitle()
        }

        validateElements()
        return tokens
    }

    // MARK: - Keyword Search

    private func searchForKeywords() {
        for i in 0..<tokens.count {
            let token = tokens[i]
            guard token.category == .unknown else { continue }

            var word = token.content
            trimString(&word, " -")
            guard !word.isEmpty else { continue }
            if word.count != 8 && isNumericString(word) { continue }

            let keyword = KeywordManager.shared.normalize(word)
            var category: ElementCategory = .unknown
            var kwOptions = KeywordOptions()

            if KeywordManager.shared.find(str: keyword, category: &category, options: &kwOptions) {
                if !options.parseReleaseGroup && category == .releaseGroup { continue }
                if !isElementCategorySearchable(category) || !kwOptions.searchable { continue }
                if isElementCategorySingular(category) && !elements.isEmpty(category) { continue }

                if category == .animeSeasonPrefix {
                    checkAnimeSeasonKeyword(i)
                    continue
                } else if category == .episodePrefix {
                    if kwOptions.valid {
                        checkExtentKeyword(.episodeNumber, i)
                    }
                    continue
                } else if category == .releaseVersion {
                    word = String(word.dropFirst()) // remove 'v'
                } else if category == .volumePrefix {
                    checkExtentKeyword(.volumeNumber, i)
                    continue
                }
            } else {
                if elements.isEmpty(.fileChecksum) && isCrc32(word) {
                    category = .fileChecksum
                } else if elements.isEmpty(.videoResolution) && isResolution(word) {
                    category = .videoResolution
                }
            }

            if category != .unknown {
                elements.insert(category, word)
                if kwOptions.identifiable {
                    tokens[i].category = .identifier
                }
            }
        }
    }

    // MARK: - Episode Number Search

    private func searchForEpisodeNumber() {
        var numberTokens: [Int] = []
        for i in 0..<tokens.count {
            if tokens[i].category == .unknown {
                if findNumberInString(tokens[i].content) != nil {
                    numberTokens.append(i)
                }
            }
        }
        guard !numberTokens.isEmpty else { return }

        foundEpisodeKeywords = !elements.isEmpty(.episodeNumber)

        if searchForEpisodePatterns(&numberTokens) { return }
        if !elements.isEmpty(.episodeNumber) { return }

        // Keep only purely numeric tokens
        numberTokens = numberTokens.filter { isNumericString(tokens[$0].content) }
        guard !numberTokens.isEmpty else { return }

        if searchForEquivalentNumbers(&numberTokens) { return }
        if searchForSeparatedNumbers(&numberTokens) { return }
        if searchForIsolatedNumbers(&numberTokens) { return }
        _ = searchForLastNumber(&numberTokens)
    }

    // MARK: - Episode Patterns

    private func searchForEpisodePatterns(_ tokenIndices: inout [Int]) -> Bool {
        for tokenIndex in tokenIndices {
            let numericFront = tokens[tokenIndex].content.first.map { isNumericChar($0) } ?? false

            if !numericFront {
                if numberComesAfterPrefix(.episodePrefix, tokenIndex) { return true }
                if numberComesAfterPrefix(.volumePrefix, tokenIndex) { continue }
            } else {
                if numberComesBeforeAnotherNumber(tokenIndex) { return true }
            }

            if matchEpisodePatterns(tokens[tokenIndex].content, tokenIndex) { return true }
        }
        return false
    }

    private func numberComesAfterPrefix(_ category: ElementCategory, _ tokenIndex: Int) -> Bool {
        guard let numberBegin = findNumberInString(tokens[tokenIndex].content) else { return false }
        let content = tokens[tokenIndex].content
        let prefixEnd = content.index(content.startIndex, offsetBy: numberBegin)
        let prefix = KeywordManager.shared.normalize(String(content[content.startIndex..<prefixEnd]))

        if KeywordManager.shared.find(category: category, str: prefix) {
            let number = String(content[prefixEnd...])
            switch category {
            case .episodePrefix:
                if !matchEpisodePatterns(number, tokenIndex) {
                    _ = setEpisodeNumber(number, tokenIndex, validate: false)
                }
                return true
            case .volumePrefix:
                if !matchVolumePatterns(number, tokenIndex) {
                    _ = setVolumeNumber(number, tokenIndex, validate: false)
                }
                return true
            default:
                break
            }
        }
        return false
    }

    private func numberComesBeforeAnotherNumber(_ tokenIndex: Int) -> Bool {
        guard let sepIdx = findNextToken(in: tokens, after: tokenIndex, flags: .flagNotDelimiter) else { return false }

        let separators: [(String, Bool)] = [("&", true), ("of", false)]
        for sep in separators {
            if isStringEqualTo(tokens[sepIdx].content, sep.0) {
                if let otherIdx = findNextToken(in: tokens, after: sepIdx, flags: .flagNotDelimiter),
                   isNumericString(tokens[otherIdx].content) {
                    _ = setEpisodeNumber(tokens[tokenIndex].content, tokenIndex, validate: false)
                    if sep.1 {
                        _ = setEpisodeNumber(tokens[otherIdx].content, otherIdx, validate: false)
                    }
                    tokens[sepIdx].category = .identifier
                    tokens[otherIdx].category = .identifier
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Pattern Matchers

    private func matchEpisodePatterns(_ word: String, _ tokenIndex: Int) -> Bool {
        if isNumericString(word) { return false }
        var w = word
        trimString(&w, " -")
        guard !w.isEmpty else { return false }

        let numericFront = w.first.map { isNumericChar($0) } ?? false
        let numericBack = w.last.map { isNumericChar($0) } ?? false

        // e.g. "01v2"
        if numericFront && numericBack {
            if matchSingleEpisodePattern(w, tokenIndex) { return true }
        }
        // e.g. "01-02", "03-05v2"
        if numericFront && numericBack {
            if matchMultiEpisodePattern(w, tokenIndex) { return true }
        }
        // e.g. "2x01", "S01E03"
        if numericBack {
            if matchSeasonAndEpisodePattern(w, tokenIndex) { return true }
        }
        // e.g. "ED1", "OP4a", "OVA2"
        if !numericFront {
            if matchTypeAndEpisodePattern(w, tokenIndex) { return true }
        }
        // e.g. "07.5"
        if numericFront && numericBack {
            if matchFractionalEpisodePattern(w, tokenIndex) { return true }
        }
        // e.g. "4a", "111C"
        if numericFront && !numericBack {
            if matchPartialEpisodePattern(w, tokenIndex) { return true }
        }
        // e.g. "#01", "#02-03v2"
        if numericBack {
            if matchNumberSignPattern(w, tokenIndex) { return true }
        }
        // Japanese counter: 第01話
        if numericFront {
            if matchJapaneseCounterPattern(w, tokenIndex) { return true }
        }

        return false
    }

    private func matchSingleEpisodePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        // Pattern: (\d{1,4})[vV](\d)
        let regex = try! NSRegularExpression(pattern: #"^(\d{1,4})[vV](\d)$"#)
        let nsRange = NSRange(word.startIndex..., in: word)
        guard let result = regex.firstMatch(in: word, range: nsRange),
              let r1 = Range(result.range(at: 1), in: word),
              let r2 = Range(result.range(at: 2), in: word) else { return false }
        _ = setEpisodeNumber(String(word[r1]), tokenIndex, validate: false)
        elements.insert(.releaseVersion, String(word[r2]))
        return true
    }

    private func matchMultiEpisodePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        // Pattern: (\d{1,4})(?:[vV](\d))?[-~&+](\d{1,4})(?:[vV](\d))?
        let regex = try! NSRegularExpression(pattern: #"^(\d{1,4})(?:[vV](\d))?[-~&+](\d{1,4})(?:[vV](\d))?$"#)
        let nsRange = NSRange(word.startIndex..., in: word)
        guard let result = regex.firstMatch(in: word, range: nsRange),
              let r1 = Range(result.range(at: 1), in: word),
              let r3 = Range(result.range(at: 3), in: word) else { return false }

        let lower = String(word[r1])
        let upper = String(word[r3])
        guard stringToInt(lower) < stringToInt(upper) else { return false }

        if setEpisodeNumber(lower, tokenIndex, validate: true) {
            _ = setEpisodeNumber(upper, tokenIndex, validate: false)
            if let r2 = Range(result.range(at: 2), in: word) {
                elements.insert(.releaseVersion, String(word[r2]))
            }
            if let r4 = Range(result.range(at: 4), in: word) {
                elements.insert(.releaseVersion, String(word[r4]))
            }
            return true
        }
        return false
    }

    private func matchSeasonAndEpisodePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        // S?(\d{1,2})(?:-S?(\d{1,2}))?(?:x|[ ._-x]?E)(\d{1,4})(?:-E?(\d{1,4}))?(?:[vV](\d))?
        let regex = try! NSRegularExpression(
            pattern: #"^S?(\d{1,2})(?:-S?(\d{1,2}))?(?:x|[ ._\-x]?E)(\d{1,4})(?:-E?(\d{1,4}))?(?:[vV](\d))?$"#,
            options: .caseInsensitive)
        let nsRange = NSRange(word.startIndex..., in: word)
        guard let result = regex.firstMatch(in: word, range: nsRange),
              let r1 = Range(result.range(at: 1), in: word),
              let r3 = Range(result.range(at: 3), in: word) else { return false }

        let season = String(word[r1])
        if stringToInt(season) == 0 { return false }

        elements.insert(.animeSeason, season)
        if let r2 = Range(result.range(at: 2), in: word) {
            elements.insert(.animeSeason, String(word[r2]))
        }
        _ = setEpisodeNumber(String(word[r3]), tokenIndex, validate: false)
        if let r4 = Range(result.range(at: 4), in: word) {
            _ = setEpisodeNumber(String(word[r4]), tokenIndex, validate: false)
        }
        return true
    }

    private func matchTypeAndEpisodePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        guard let numberBegin = findNumberInString(word) else { return false }
        let prefixEnd = word.index(word.startIndex, offsetBy: numberBegin)
        let prefix = String(word[word.startIndex..<prefixEnd])
        let normalized = KeywordManager.shared.normalize(prefix)

        var category: ElementCategory = .animeType
        var kwOptions = KeywordOptions()
        guard KeywordManager.shared.find(str: normalized, category: &category, options: &kwOptions) else { return false }

        elements.insert(.animeType, prefix)
        let number = String(word[prefixEnd...])

        if matchEpisodePatterns(number, tokenIndex) || setEpisodeNumber(number, tokenIndex, validate: true) {
            // Split token: update content to number only
            tokens[tokenIndex].content = number
            return true
        }
        return false
    }

    private func matchFractionalEpisodePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        // Only allow .5 fractional
        guard word.range(of: #"^\d+\.5$"#, options: .regularExpression) != nil else { return false }
        return setEpisodeNumber(word, tokenIndex, validate: true)
    }

    private func matchPartialEpisodePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        // Number followed by single letter A-C or a-c
        guard let lastChar = word.last else { return false }
        let isValidSuffix = (lastChar >= "A" && lastChar <= "C") || (lastChar >= "a" && lastChar <= "c")
        guard isValidSuffix else { return false }

        // Everything before the last char must be numeric
        let numPart = word.dropLast()
        guard !numPart.isEmpty && numPart.allSatisfy({ isNumericChar($0) }) else { return false }

        return setEpisodeNumber(word, tokenIndex, validate: true)
    }

    private func matchNumberSignPattern(_ word: String, _ tokenIndex: Int) -> Bool {
        guard word.first == "#" else { return false }
        let regex = try! NSRegularExpression(pattern: #"^#(\d{1,4})(?:[-~&+](\d{1,4}))?(?:[vV](\d))?$"#)
        let nsRange = NSRange(word.startIndex..., in: word)
        guard let result = regex.firstMatch(in: word, range: nsRange),
              let r1 = Range(result.range(at: 1), in: word) else { return false }

        if setEpisodeNumber(String(word[r1]), tokenIndex, validate: true) {
            if let r2 = Range(result.range(at: 2), in: word) {
                _ = setEpisodeNumber(String(word[r2]), tokenIndex, validate: false)
            }
            if let r3 = Range(result.range(at: 3), in: word) {
                elements.insert(.releaseVersion, String(word[r3]))
            }
            return true
        }
        return false
    }

    private func matchJapaneseCounterPattern(_ word: String, _ tokenIndex: Int) -> Bool {
        // U+8A71 is 話 (counter for episodes)
        guard word.last == "\u{8A71}" else { return false }
        let regex = try! NSRegularExpression(pattern: #"^(\d{1,4})\u{8A71}$"#)
        let nsRange = NSRange(word.startIndex..., in: word)
        guard let result = regex.firstMatch(in: word, range: nsRange),
              let r1 = Range(result.range(at: 1), in: word) else { return false }
        _ = setEpisodeNumber(String(word[r1]), tokenIndex, validate: false)
        return true
    }

    // MARK: - Volume Patterns

    private func matchVolumePatterns(_ word: String, _ tokenIndex: Int) -> Bool {
        if isNumericString(word) { return false }
        var w = word
        trimString(&w, " -")
        guard !w.isEmpty else { return false }

        let numericFront = w.first.map { isNumericChar($0) } ?? false
        let numericBack = w.last.map { isNumericChar($0) } ?? false

        if numericFront && numericBack {
            if matchSingleVolumePattern(w, tokenIndex) { return true }
            if matchMultiVolumePattern(w, tokenIndex) { return true }
        }
        return false
    }

    private func matchSingleVolumePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"^(\d{1,2})[vV](\d)$"#)
        let nsRange = NSRange(word.startIndex..., in: word)
        guard let result = regex.firstMatch(in: word, range: nsRange),
              let r1 = Range(result.range(at: 1), in: word),
              let r2 = Range(result.range(at: 2), in: word) else { return false }
        _ = setVolumeNumber(String(word[r1]), tokenIndex, validate: false)
        elements.insert(.releaseVersion, String(word[r2]))
        return true
    }

    private func matchMultiVolumePattern(_ word: String, _ tokenIndex: Int) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"^(\d{1,2})[-~&+](\d{1,2})(?:[vV](\d))?$"#)
        let nsRange = NSRange(word.startIndex..., in: word)
        guard let result = regex.firstMatch(in: word, range: nsRange),
              let r1 = Range(result.range(at: 1), in: word),
              let r2 = Range(result.range(at: 2), in: word) else { return false }
        let lower = String(word[r1])
        let upper = String(word[r2])
        guard stringToInt(lower) < stringToInt(upper) else { return false }
        if setVolumeNumber(lower, tokenIndex, validate: true) {
            _ = setVolumeNumber(upper, tokenIndex, validate: false)
            if let r3 = Range(result.range(at: 3), in: word) {
                elements.insert(.releaseVersion, String(word[r3]))
            }
            return true
        }
        return false
    }

    // MARK: - Equivalent / Separated / Isolated / Last Number

    private func searchForEquivalentNumbers(_ tokenIndices: inout [Int]) -> Bool {
        for tokenIndex in tokenIndices {
            guard !isTokenIsolated(tokenIndex),
                  isValidEpisodeNumber(tokens[tokenIndex].content) else { continue }

            guard let nextIdx = findNextToken(in: tokens, after: tokenIndex, flags: .flagNotDelimiter),
                  tokens[nextIdx].category == .bracket else { continue }

            guard let enclosedIdx = findNextToken(in: tokens, after: nextIdx, flags: [.flagEnclosed, .flagNotDelimiter]),
                  tokens[enclosedIdx].category == .unknown,
                  isTokenIsolated(enclosedIdx),
                  isNumericString(tokens[enclosedIdx].content),
                  isValidEpisodeNumber(tokens[enclosedIdx].content) else { continue }

            let val1 = stringToInt(tokens[tokenIndex].content)
            let val2 = stringToInt(tokens[enclosedIdx].content)
            let (minIdx, maxIdx) = val1 < val2 ? (tokenIndex, enclosedIdx) : (enclosedIdx, tokenIndex)

            _ = setEpisodeNumber(tokens[minIdx].content, minIdx, validate: false)
            setAlternativeEpisodeNumber(tokens[maxIdx].content, maxIdx)
            return true
        }
        return false
    }

    private func searchForSeparatedNumbers(_ tokenIndices: inout [Int]) -> Bool {
        for tokenIndex in tokenIndices {
            guard let prevIdx = findPreviousToken(in: tokens, before: tokenIndex, flags: .flagNotDelimiter),
                  tokens[prevIdx].category == .unknown,
                  isDashCharacter(tokens[prevIdx].content) else { continue }

            if setEpisodeNumber(tokens[tokenIndex].content, tokenIndex, validate: true) {
                tokens[prevIdx].category = .identifier
                return true
            }
        }
        return false
    }

    private func searchForIsolatedNumbers(_ tokenIndices: inout [Int]) -> Bool {
        for tokenIndex in tokenIndices {
            guard tokens[tokenIndex].enclosed, isTokenIsolated(tokenIndex) else { continue }
            if setEpisodeNumber(tokens[tokenIndex].content, tokenIndex, validate: true) {
                return true
            }
        }
        return false
    }

    private func searchForLastNumber(_ tokenIndices: inout [Int]) -> Bool {
        for tokenIndex in tokenIndices.reversed() {
            guard tokenIndex > 0 else { continue }
            guard !tokens[tokenIndex].enclosed else { continue }

            // Ignore if first non-enclosed non-delimiter token
            let allPriorEnclosed = tokens[0..<tokenIndex].allSatisfy {
                $0.enclosed || $0.category == .delimiter
            }
            if allPriorEnclosed { continue }

            // Ignore if previous token is "Movie" or "Part"
            if let prevIdx = findPreviousToken(in: tokens, before: tokenIndex, flags: .flagNotDelimiter),
               tokens[prevIdx].category == .unknown {
                if isStringEqualTo(tokens[prevIdx].content, "Movie") ||
                   isStringEqualTo(tokens[prevIdx].content, "Part") {
                    continue
                }
            }

            if setEpisodeNumber(tokens[tokenIndex].content, tokenIndex, validate: true) {
                return true
            }
        }
        return false
    }

    // MARK: - Episode/Volume number setters

    @discardableResult
    private func setEpisodeNumber(_ number: String, _ tokenIndex: Int, validate: Bool) -> Bool {
        if validate && !isValidEpisodeNumber(number) { return false }

        tokens[tokenIndex].category = .identifier
        var category: ElementCategory = .episodeNumber

        if foundEpisodeKeywords {
            for (i, pair) in elements.pairs.enumerated() {
                guard pair.0 == .episodeNumber else { continue }
                let comparison = stringToInt(number) - stringToInt(pair.1)
                if comparison > 0 {
                    category = .episodeNumberAlt
                } else if comparison < 0 {
                    elements.setCategoryAt(index: i, .episodeNumberAlt)
                } else {
                    return false // same number
                }
                break
            }
        }

        elements.insert(category, number)
        return true
    }

    @discardableResult
    private func setAlternativeEpisodeNumber(_ number: String, _ tokenIndex: Int) -> Bool {
        elements.insert(.episodeNumberAlt, number)
        tokens[tokenIndex].category = .identifier
        return true
    }

    @discardableResult
    private func setVolumeNumber(_ number: String, _ tokenIndex: Int, validate: Bool) -> Bool {
        if validate && !isValidVolumeNumber(number) { return false }
        elements.insert(.volumeNumber, number)
        tokens[tokenIndex].category = .identifier
        return true
    }

    private func isValidEpisodeNumber(_ number: String) -> Bool {
        stringToInt(number) <= kEpisodeNumberMax
    }

    private func isValidVolumeNumber(_ number: String) -> Bool {
        stringToInt(number) <= kVolumeNumberMax
    }

    // MARK: - Anime Title Search

    private func searchForAnimeTitle() {
        var enclosedTitle = false
        var tokenBeginIdx: Int?

        // Find first non-enclosed unknown token
        tokenBeginIdx = findToken(in: tokens, from: 0, to: tokens.count,
                                  flags: [.flagNotEnclosed, .flagUnknown])

        if tokenBeginIdx == nil {
            enclosedTitle = true
            var searchFrom = 0
            var skippedPreviousGroup = false

            while true {
                guard let idx = findToken(in: tokens, from: searchFrom, to: tokens.count, flags: .flagUnknown) else { break }

                if isMostlyLatinString(tokens[idx].content) && skippedPreviousGroup {
                    tokenBeginIdx = idx
                    break
                }

                // Get first unknown token of next group
                guard let bracketIdx = findToken(in: tokens, from: idx, to: tokens.count, flags: .flagBracket) else { break }
                guard let nextUnknown = findToken(in: tokens, from: bracketIdx, to: tokens.count, flags: .flagUnknown) else { break }
                searchFrom = nextUnknown
                skippedPreviousGroup = true
            }
        }

        guard let beginIdx = tokenBeginIdx else { return }

        // Find end: next identifier (or bracket if enclosed)
        var flags: TokenFlag = .flagIdentifier
        if enclosedTitle { flags.insert(.flagBracket) }
        let tokenEndIdx = findToken(in: tokens, from: beginIdx, to: tokens.count, flags: flags) ?? tokens.count

        var endIdx = tokenEndIdx

        // Handle unmatched brackets
        if !enclosedTitle {
            var lastBracket = endIdx
            var bracketOpen = false
            for i in beginIdx..<endIdx {
                if tokens[i].category == .bracket {
                    lastBracket = i
                    bracketOpen = !bracketOpen
                }
            }
            if bracketOpen { endIdx = lastBracket }
        }

        // Handle trailing enclosed groups
        if !enclosedTitle {
            var checkIdx = endIdx
            while let prevIdx = findPreviousToken(in: tokens, before: checkIdx, flags: .flagNotDelimiter),
                  tokens[prevIdx].category == .bracket,
                  tokens[prevIdx].content.first != ")" {
                if let bracketStart = findPreviousToken(in: tokens, before: prevIdx, flags: .flagBracket) {
                    endIdx = bracketStart
                    checkIdx = bracketStart
                } else {
                    break
                }
            }
        }

        buildElement(.animeTitle, keepDelimiters: false, from: beginIdx, to: endIdx)
    }

    // MARK: - Release Group Search

    private func searchForReleaseGroup() {
        var searchFrom = 0

        while true {
            guard let beginIdx = findToken(in: tokens, from: searchFrom, to: tokens.count,
                                           flags: [.flagEnclosed, .flagUnknown]) else { return }

            let endIdx = findToken(in: tokens, from: beginIdx, to: tokens.count,
                                   flags: [.flagBracket, .flagIdentifier]) ?? tokens.count
            searchFrom = endIdx

            guard endIdx < tokens.count && tokens[endIdx].category == .bracket else { continue }

            // Ignore if not first non-delimiter token in group
            if let prevIdx = findPreviousToken(in: tokens, before: beginIdx, flags: .flagNotDelimiter),
               tokens[prevIdx].category != .bracket {
                continue
            }

            buildElement(.releaseGroup, keepDelimiters: true, from: beginIdx, to: endIdx)
            return
        }
    }

    // MARK: - Episode Title Search

    private func searchForEpisodeTitle() {
        var searchFrom = 0

        while true {
            guard let beginIdx = findToken(in: tokens, from: searchFrom, to: tokens.count,
                                           flags: [.flagNotEnclosed, .flagUnknown]) else { return }

            let endIdx = findToken(in: tokens, from: beginIdx, to: tokens.count,
                                   flags: [.flagBracket, .flagIdentifier]) ?? tokens.count
            searchFrom = endIdx

            // Ignore if only a dash
            if endIdx - beginIdx <= 2 && isDashCharacter(tokens[beginIdx].content) { continue }

            buildElement(.episodeTitle, keepDelimiters: false, from: beginIdx, to: endIdx)
            return
        }
    }

    // MARK: - Isolated Numbers (year, resolution)

    private func searchForIsolatedNumbersGlobal() {
        for i in 0..<tokens.count {
            guard tokens[i].category == .unknown,
                  isNumericString(tokens[i].content),
                  isTokenIsolated(i) else { continue }

            let number = stringToInt(tokens[i].content)

            if number >= kAnimeYearMin && number <= kAnimeYearMax && elements.isEmpty(.animeYear) {
                elements.insert(.animeYear, tokens[i].content)
                tokens[i].category = .identifier
                continue
            }

            if (number == 480 || number == 720 || number == 1080) && elements.isEmpty(.videoResolution) {
                elements.insert(.videoResolution, tokens[i].content)
                tokens[i].category = .identifier
                continue
            }
        }
    }

    // MARK: - Validate

    private func validateElements() {
        guard !elements.isEmpty(.animeType) && !elements.isEmpty(.episodeTitle) else { return }
        let episodeTitle = elements.get(.episodeTitle)

        var i = 0
        while i < elements.count {
            let pair = elements.pairs[i]
            if pair.0 == .animeType {
                if episodeTitle.range(of: pair.1, options: .caseInsensitive) != nil {
                    if episodeTitle.count == pair.1.count {
                        elements.erase(.episodeTitle)
                    } else {
                        let keyword = KeywordManager.shared.normalize(pair.1)
                        if KeywordManager.shared.find(category: .animeType, str: keyword) {
                            elements.eraseAt(index: i)
                            continue
                        }
                    }
                }
            }
            i += 1
        }
    }

    // MARK: - Helpers

    private func findNumberInString(_ str: String) -> Int? {
        for (i, c) in str.enumerated() {
            if isNumericChar(c) { return i }
        }
        return nil
    }

    private func isCrc32(_ str: String) -> Bool {
        str.count == 8 && isHexadecimalString(str)
    }

    private func isDashCharacter(_ str: String) -> Bool {
        guard str.count == 1, let c = str.first else { return false }
        return kDashes.contains(c)
    }

    private func isResolution(_ str: String) -> Bool {
        // ###x### or ###p
        let chars = Array(str)
        let minWidthSize = 3
        let minHeightSize = 3

        if chars.count >= minWidthSize + 1 + minHeightSize {
            for (i, c) in chars.enumerated() {
                if c == "x" || c == "X" || c == "\u{00D7}" {
                    if i >= minWidthSize && i <= chars.count - (minHeightSize + 1) {
                        var allNumeric = true
                        for j in 0..<chars.count {
                            if j != i && !isNumericChar(chars[j]) {
                                allNumeric = false
                                break
                            }
                        }
                        if allNumeric { return true }
                    }
                }
            }
        } else if chars.count >= minHeightSize + 1 {
            if chars.last == "p" || chars.last == "P" {
                let allNumeric = chars.dropLast().allSatisfy { isNumericChar($0) }
                if allNumeric { return true }
            }
        }

        return false
    }

    private func isTokenIsolated(_ tokenIndex: Int) -> Bool {
        guard let prevIdx = findPreviousToken(in: tokens, before: tokenIndex, flags: .flagNotDelimiter),
              tokens[prevIdx].category == .bracket else { return false }
        guard let nextIdx = findNextToken(in: tokens, after: tokenIndex, flags: .flagNotDelimiter),
              tokens[nextIdx].category == .bracket else { return false }
        return true
    }

    private func checkAnimeSeasonKeyword(_ tokenIndex: Int) {
        if let prevIdx = findPreviousToken(in: tokens, before: tokenIndex, flags: .flagNotDelimiter) {
            let number = getNumberFromOrdinal(tokens[prevIdx].content)
            if !number.isEmpty {
                elements.insert(.animeSeason, number)
                tokens[prevIdx].category = .identifier
                tokens[tokenIndex].category = .identifier
                return
            }
        }
        if let nextIdx = findNextToken(in: tokens, after: tokenIndex, flags: .flagNotDelimiter),
           isNumericString(tokens[nextIdx].content) {
            elements.insert(.animeSeason, tokens[nextIdx].content)
            tokens[tokenIndex].category = .identifier
            tokens[nextIdx].category = .identifier
        }
    }

    private func checkExtentKeyword(_ category: ElementCategory, _ tokenIndex: Int) {
        guard let nextIdx = findNextToken(in: tokens, after: tokenIndex, flags: .flagNotDelimiter),
              tokens[nextIdx].category == .unknown else { return }

        if let pos = findNumberInString(tokens[nextIdx].content), pos == 0 {
            switch category {
            case .episodeNumber:
                if !matchEpisodePatterns(tokens[nextIdx].content, nextIdx) {
                    _ = setEpisodeNumber(tokens[nextIdx].content, nextIdx, validate: false)
                }
            case .volumeNumber:
                if !matchVolumePatterns(tokens[nextIdx].content, nextIdx) {
                    _ = setVolumeNumber(tokens[nextIdx].content, nextIdx, validate: false)
                }
            default:
                return
            }
            tokens[tokenIndex].category = .identifier
        }
    }

    private func getNumberFromOrdinal(_ word: String) -> String {
        let ordinals: [String: String] = [
            "1st": "1", "First": "1",
            "2nd": "2", "Second": "2",
            "3rd": "3", "Third": "3",
            "4th": "4", "Fourth": "4",
            "5th": "5", "Fifth": "5",
            "6th": "6", "Sixth": "6",
            "7th": "7", "Seventh": "7",
            "8th": "8", "Eighth": "8",
            "9th": "9", "Ninth": "9",
        ]
        return ordinals[word] ?? ""
    }

    private func isElementCategorySearchable(_ category: ElementCategory) -> Bool {
        switch category {
        case .animeSeasonPrefix, .animeType, .audioTerm, .deviceCompatibility,
             .episodePrefix, .fileChecksum, .language, .other, .releaseGroup,
             .releaseInformation, .releaseVersion, .source, .subtitles,
             .videoResolution, .videoTerm, .volumePrefix:
            return true
        default:
            return false
        }
    }

    private func isElementCategorySingular(_ category: ElementCategory) -> Bool {
        switch category {
        case .animeSeason, .animeType, .audioTerm, .deviceCompatibility,
             .episodeNumber, .language, .other, .releaseInformation,
             .source, .videoTerm:
            return false
        default:
            return true
        }
    }

    private func buildElement(_ category: ElementCategory, keepDelimiters: Bool, from: Int, to: Int) {
        var element = ""
        for i in from..<to {
            switch tokens[i].category {
            case .unknown:
                element += tokens[i].content
                tokens[i].category = .identifier
            case .bracket:
                element += tokens[i].content
            case .delimiter:
                let delimiter = tokens[i].content.first!
                if keepDelimiters {
                    element.append(delimiter)
                } else if i != from && i != to {
                    switch delimiter {
                    case ",", "&":
                        element.append(delimiter)
                    default:
                        element.append(" ")
                    }
                }
            default:
                break
            }
        }

        if !keepDelimiters {
            trimString(&element, kDashesWithSpace)
        }

        if !element.isEmpty {
            elements.insert(category, element)
        }
    }
}

// MARK: - Main Anitomy class

final class Anitomy {
    private let elements = AnitomyElements()
    private var options = AnitomyOptions()
    private var tokens: [AnitomyToken] = []

    /// Parse an anime filename and extract structured elements.
    @discardableResult
    func parse(_ filename: String) -> Bool {
        elements.clear()
        tokens.removeAll()

        var name = filename

        if options.parseFileExtension {
            if let (stripped, ext) = removeExtension(from: name) {
                name = stripped
                elements.insert(.fileExtension, ext)
            }
        }

        for ignored in options.ignoredStrings {
            name = name.replacingOccurrences(of: ignored, with: "")
        }

        guard !name.isEmpty else { return false }
        elements.insert(.fileName, name)

        let tokenizer = AnitomyTokenizer(filename: name, elements: elements,
                                         options: options, tokens: &tokens)
        tokens = tokenizer.tokenize()
        guard !tokens.isEmpty else { return false }

        let parser = AnitomyParser(elements: elements, options: options, tokens: &tokens)
        tokens = parser.parse()

        return !elements.isEmpty(.animeTitle)
    }

    /// Access parsed elements.
    func get(_ category: ElementCategory) -> String {
        elements.get(category)
    }

    func getAll(_ category: ElementCategory) -> [String] {
        elements.getAll(category)
    }

    var allElements: AnitomyElements { elements }

    // MARK: - Extension removal

    private func removeExtension(from filename: String) -> (String, String)? {
        guard let dotIndex = filename.lastIndex(of: ".") else { return nil }
        let ext = String(filename[filename.index(after: dotIndex)...])

        guard ext.count <= 4, isAlphanumericString(ext) else { return nil }

        let keyword = KeywordManager.shared.normalize(ext)
        guard KeywordManager.shared.find(category: .fileExtension, str: keyword) else { return nil }

        let stripped = String(filename[filename.startIndex..<dotIndex])
        return (stripped, ext)
    }
}
