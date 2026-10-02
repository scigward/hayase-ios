//
//  CommandScore.swift
//  Hayase
//
//  Mirrors: cmdk-sv's `internal/command-score.js`, the filter every `Command` list uses.
//

import Foundation

enum CommandScore {
    private static let continueMatch = 1.0
    private static let spaceWordJump = 0.9
    private static let nonSpaceWordJump = 0.8
    private static let characterJump = 0.17
    private static let transposition = 0.1
    private static let penaltySkipped = 0.999
    private static let penaltyCaseMismatch = 0.9999
    private static let penaltyNotComplete = 0.99

    private static let gapCharacters = Set<Character>("\\/_+.#\"@[({&")

    private static func isGap(_ character: Character?) -> Bool {
        character.map { gapCharacters.contains($0) } ?? false
    }

    /// `/[\s-]/`
    private static func isSpace(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character == "-" || character.isWhitespace
    }

    /// How well `abbreviation` matches `string`; 0 is no match. cmdk lowercases and trims the value
    /// of an item before scoring it, and hands the search over as typed.
    static func score(value: String, search: String) -> Double {
        let trimmed = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let string = Array(trimmed)
        let abbreviation = Array(search)
        var memo: [Int: Double] = [:]
        return inner(string, abbreviation,
                     format(string), format(abbreviation),
                     stringIndex: 0, abbreviationIndex: 0, memo: &memo)
    }

    /// `formatInput`: lowercase, and every space or hyphen becomes a plain space.
    private static func format(_ characters: [Character]) -> [Character] {
        // one character for one, so the indexes of the lowercase copy are the original's
        characters.map { character in
            isSpace(character) ? " " : (String(character).lowercased().first ?? character)
        }
    }

    private static func indexOf(_ character: Character, in string: [Character], from start: Int) -> Int? {
        guard start >= 0, start < string.count else { return nil }
        return string[start...].firstIndex(of: character)
    }

    private static func count(_ predicate: (Character) -> Bool, in string: [Character], from start: Int, to end: Int) -> Int {
        guard start < end, start >= 0, end <= string.count else { return 0 }
        return string[start..<end].filter(predicate).count
    }

    private static func inner(_ string: [Character], _ abbreviation: [Character],
                              _ lowerString: [Character], _ lowerAbbreviation: [Character],
                              stringIndex: Int, abbreviationIndex: Int,
                              memo: inout [Int: Double]) -> Double {
        if abbreviationIndex == abbreviation.count {
            return stringIndex == string.count ? continueMatch : penaltyNotComplete
        }
        let key = stringIndex * (abbreviation.count + 1) + abbreviationIndex
        if let known = memo[key] { return known }

        let abbreviationCharacter = lowerAbbreviation[abbreviationIndex]
        var index = indexOf(abbreviationCharacter, in: lowerString, from: stringIndex)
        var highScore = 0.0

        func lowerAbbreviationCharacter(_ offset: Int) -> Character? {
            let position = abbreviationIndex + offset
            return position < lowerAbbreviation.count ? lowerAbbreviation[position] : nil
        }

        while let current = index {
            var score = inner(string, abbreviation, lowerString, lowerAbbreviation,
                              stringIndex: current + 1, abbreviationIndex: abbreviationIndex + 1, memo: &memo)
            if score > highScore {
                let previous: Character? = current > 0 ? string[current - 1] : nil
                if current == stringIndex {
                    score *= continueMatch
                } else if isGap(previous) {
                    score *= nonSpaceWordJump
                    let breaks = count(gapCharacters.contains, in: string, from: stringIndex, to: current - 1)
                    if breaks > 0, stringIndex > 0 { score *= pow(penaltySkipped, Double(breaks)) }
                } else if isSpace(previous) {
                    score *= spaceWordJump
                    let breaks = count(isSpace, in: string, from: stringIndex, to: current - 1)
                    if breaks > 0, stringIndex > 0 { score *= pow(penaltySkipped, Double(breaks)) }
                } else {
                    score *= characterJump
                    if stringIndex > 0 { score *= pow(penaltySkipped, Double(current - stringIndex)) }
                }
                if string[current] != abbreviation[abbreviationIndex] {
                    score *= penaltyCaseMismatch
                }
            }

            let previousLower: Character? = current > 0 ? lowerString[current - 1] : nil
            let next = lowerAbbreviationCharacter(1)
            if (score < transposition && previousLower != nil && previousLower == next)
                || (next != nil && next == lowerAbbreviationCharacter(0) && previousLower != abbreviationCharacter) {
                let transposed = inner(string, abbreviation, lowerString, lowerAbbreviation,
                                       stringIndex: current + 1, abbreviationIndex: abbreviationIndex + 2, memo: &memo)
                if transposed * transposition > score { score = transposed * transposition }
            }
            if score > highScore { highScore = score }
            index = indexOf(abbreviationCharacter, in: lowerString, from: current + 1)
        }
        memo[key] = highScore
        return highScore
    }
}
