//
//  IRCMessage.swift
//  Hayase
//
//  Created by scigward.
//
//  A scoped, faithful port of `@thaunknown/web-irc` v1.0.3's wire-level
//  parsing — irclineparser.ts, ircmessage.ts, messagetags.ts, and
//  helpers.parseMask. Ported by downloading and reading the library's
//  actual published source rather than reconstructed from general IRC
//  knowledge, so tokenization and tag-escaping rules match exactly.
//
//  Scope note: the full library (~4,000 lines) also implements CAP
//  negotiation, SASL, WHO/WHOX, mode parsing, and much more. This port only
//  covers the wire-format layer (parsing/serializing one line) — see
//  IRCClient.swift for which commands are actually handled, which is a
//  deliberately narrower set matching what interface's chat feature uses.

import Foundation

/// A parsed (or about-to-be-serialized) IRC protocol line.
/// Mirrors the library's `IrcMessage` class.
struct IRCMessage {
    var tags: [String: String] = [:]
    var prefix: String = ""
    var nick: String = ""
    var ident: String = ""
    var hostname: String = ""
    var command: String = ""
    var params: [String] = []

    init() {}

    init(command: String, params: [String] = []) {
        self.command = command
        self.params = params
    }

    /// Serializes back to a wire-format line. Mirrors `IrcMessage.to1459()`.
    func serialized() -> String {
        var parts: [String] = []
        let encodedTags = IRCMessageTags.encode(tags)
        if !encodedTags.isEmpty {
            parts.append("@" + encodedTags)
        }
        if !prefix.isEmpty {
            parts.append(":" + prefix)
        }
        parts.append(command)
        for (index, param) in params.enumerated() {
            if index == params.count - 1, param.contains(" ") || param.hasPrefix(":") {
                parts.append(":" + param)
            } else {
                parts.append(param)
            }
        }
        return parts.joined(separator: " ")
    }
}

/// IRCv3 message-tag encoding/decoding. Mirrors `messagetags.ts`.
enum IRCMessageTags {
    /// Mirrors `decodeValue`. Manually scans for the 5 recognized 2-character
    /// escapes rather than using a regex, since Swift has no direct
    /// equivalent of JS's ordered-alternation replace; a lone/unrecognized
    /// backslash is dropped either way, matching the library's fallback.
    static func decodeValue(_ value: String) -> String {
        let chars = Array(value)
        var result = ""
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\" {
                if i + 1 < chars.count {
                    switch chars[i + 1] {
                    case "\\": result.append("\\"); i += 2
                    case ":": result.append(";"); i += 2
                    case "s": result.append(" "); i += 2
                    case "n": result.append("\n"); i += 2
                    case "r": result.append("\r"); i += 2
                    default: i += 1 // unrecognized escape — drop just the backslash
                    }
                } else {
                    i += 1 // trailing lone backslash — dropped
                }
            } else {
                result.append(chars[i])
                i += 1
            }
        }
        return result
    }

    /// Mirrors `encodeValue`.
    static func encodeValue(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "\\": result += "\\\\"
            case ";": result += "\\:"
            case " ": result += "\\s"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            default: result.append(ch)
            }
        }
        return result
    }

    /// Mirrors `decode`.
    static func decode(_ tagString: String) -> [String: String] {
        var tags: [String: String] = [:]
        for rawTag in tagString.split(separator: ";", omittingEmptySubsequences: false) {
            let tag = String(rawTag)
            guard let equalsIndex = tag.firstIndex(of: "=") else {
                let key = tag.lowercased()
                if !key.isEmpty { tags[key] = "" }
                continue
            }
            let key = String(tag[..<equalsIndex]).lowercased()
            guard !key.isEmpty else { continue }
            tags[key] = decodeValue(String(tag[tag.index(after: equalsIndex)...]))
        }
        return tags
    }

    /// Mirrors `encode`.
    static func encode(_ tags: [String: String], separator: String = ";") -> String {
        tags.map { key, value in "\(key)=\(encodeValue(value))" }.joined(separator: separator)
    }
}

/// Splits a `nick!ident@host` mask into its parts. Mirrors `Helpers.parseMask`.
enum IRCMask {
    static func parse(_ mask: String) -> (nick: String, user: String, host: String) {
        let bang = mask.firstIndex(of: "!")
        let at = mask.firstIndex(of: "@")

        switch (bang, at) {
        case (nil, nil):
            return mask.contains(".") ? ("", "", mask) : (mask, "", "")
        case (nil, .some(let atIdx)):
            return (String(mask[..<atIdx]), "", String(mask[mask.index(after: atIdx)...]))
        case (.some(let bangIdx), nil):
            return (String(mask[..<bangIdx]), String(mask[mask.index(after: bangIdx)...]), "")
        case (.some(let bangIdx), .some(let atIdx)):
            guard bangIdx < atIdx else {
                // Malformed mask (an '@' before the '!'); fall back to
                // treating the whole thing as a nick rather than crash on
                // an invalid range.
                return (mask, "", "")
            }
            return (String(mask[..<bangIdx]),
                    String(mask[mask.index(after: bangIdx)..<atIdx]),
                    String(mask[mask.index(after: atIdx)...]))
        }
    }
}

/// Tokenizes a raw wire line into an `IRCMessage`. Mirrors `parseIrcLine`.
enum IRCLineParser {
    static func parse(_ rawLine: String) -> IRCMessage {
        let input = Array(rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")))
        var cPos = 0
        var inParams = false

        func nextToken() -> String? {
            while cPos < input.count, input[cPos] == " " { cPos += 1 }
            if cPos == input.count {
                return inParams ? nil : ""
            }
            var end = cPos
            while end < input.count, input[end] != " " { end += 1 }
            if inParams, input[cPos] == ":", cPos > 0, input[cPos - 1] == " " {
                cPos += 1
                end = input.count
            }
            let token = String(input[cPos..<end])
            cPos = end
            while cPos < input.count, input[cPos] == " " { cPos += 1 }
            return token
        }

        var message = IRCMessage()

        if cPos < input.count, input[cPos] == "@" {
            let tagToken = nextToken() ?? ""
            message.tags = IRCMessageTags.decode(String(tagToken.dropFirst()))
        }
        if cPos < input.count, input[cPos] == ":" {
            let prefixToken = nextToken() ?? ""
            message.prefix = String(prefixToken.dropFirst())
            let mask = IRCMask.parse(message.prefix)
            message.nick = mask.nick
            message.ident = mask.user
            message.hostname = mask.host
        }
        message.command = (nextToken() ?? "").uppercased()
        inParams = true
        while let token = nextToken() {
            message.params.append(token)
        }
        return message
    }
}
