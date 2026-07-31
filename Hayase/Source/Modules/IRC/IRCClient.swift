//
//  IRCClient.swift
//  Hayase
//
//  Created by scigward.
//
//  Ported from src/lib/modules/irc/index.ts (`MessageClient`), scoped to
//  exactly the commands that class actually uses: registration (NICK/USER),
//  PING/PONG keepalive, JOIN, NAMES (353/366), PRIVMSG, PART/QUIT/KICK.
//
//  Deliberate scope reductions from the full `@thaunknown/web-irc` library
//  (flagged here rather than silently — see file header of IRCMessage.swift
//  for the wire-format layer's own scope note):
//  - CAP negotiation is minimal, not absent. The real library negotiates a
//    long list in practice (cap-notify, batch, multi-prefix, message-tags,
//    draft/message-tags-0.2, away-notify, invite-notify, account-notify,
//    account-tag, server-time, userhost-in-names, extended-join, two
//    znc.in server-time variants, plus chghost/setname since interface
//    enables those). This port requests exactly two — `userhost-in-names`
//    and `multi-prefix` — and only because omitting the first one entirely
//    caused a real bug (see `handleCap`'s doc comment). Everything else
//    (server-time-accurate timestamps, away/account notifications, batch
//    framing, etc.) is still not negotiated, so PRIVMSG timestamps still
//    fall back to local receipt time rather than a server-time tag, and
//    account-related fields on users are never populated.
//  - No SASL (interface doesn't configure any SASL credentials for this
//    network either).
//  - No client-initiated periodic ping/timeout/auto-reconnect. This client
//    still replies to server-initiated PINGs (required to stay connected),
//    it just doesn't proactively ping the server itself or reconnect on
//    drop.
//  - No ISUPPORT/PREFIX-table parsing for NAMES; a fixed common set of
//    prefix symbols (~&@%+) is stripped instead of one built from the
//    server's actual PREFIX advertisement.
//  - No CASEMAPPING/case-folding: nick and channel-name comparisons
//    (self-join detection, NAMES/PRIVMSG channel scoping) use plain Swift
//    `==`. Upstream calls `ircClient.caseCompare()` for all of these, which
//    folds case per the server's advertised CASEMAPPING (rfc1459 by
//    default). Only matters if a server ever echoes a channel/nick back in
//    different casing than what was sent — uncommon for the fixed values
//    this client always uses, but a real, disclosed gap rather than a
//    guaranteed non-issue.
//  - crypt.ts (message encryption) is intentionally not ported — it's
//    present upstream but unused (both its import and its use are commented
//    out in index.ts), so there is nothing working to port.
//
//  One place this port is arguably *more* correct than upstream, flagged so
//  you can decide whether you want bug-for-bug parity instead:
//  - interface's `MessageClient.new()` resolves its second promise on the
//    very next `'join'` event of any kind (`client.irc.once('join', resolve)`,
//    not scoped to our own nick or even our own channel). In the extremely
//    unlikely case another user joins the channel in the same instant as our
//    own join confirmation, upstream could resolve "ready" on the wrong
//    event. This port explicitly checks the join is for our own channel and
//    our own (server-confirmed) nick before firing `onReady`.
//
//  Two behaviors worth flagging that are preserved as discovered, not
//  "fixed":
//  - The `kick` event's `nick`/`ident` fields identify the user who did the
//    kicking, not the user who got kicked (`kicked` is a separate field with
//    just a nick, no ident). interface's own `deleteUser(kickEvent)` deletes
//    `users[kickEvent.ident]` — i.e. it removes the *kicker* from the
//    userlist, not the person actually kicked. That looks like an upstream
//    bug, but "everything preserved" means this port reproduces it exactly
//    rather than silently kicking the right person.
//  - A guest identity's constructed nick upstream evaluates to
//    `"undefined_Guest-xxxxxx"` (JS: `${ext[0]}` where `ext` is `''` for a
//    guest becomes the string `"undefined"`). This is preserved too — it's
//    cosmetic (only visible to third-party IRC clients on the same network;
//    Hayase's own nick-parsing recovers the clean guest name regardless).
//
//  One place this port does NOT preserve upstream as-is, on purpose: if a
//  PRIVMSG arrives from an ident that isn't in the tracked userlist yet,
//  interface's TypeScript does `this.users.value[priv.ident]!` — a
//  non-null assertion that would be `undefined` at runtime, not actually
//  safe. This port falls back to a minimal synthesized user for that
//  message instead of the equivalent of a crash, since Swift has no
//  "trust me" operator that fails as quietly as a wrong ! assertion does in
//  compiled JS.

import Foundation

/// A single chat message, ready for display. Mirrors interface's
/// `ChatMessage` shape.
struct IRCChatMessage: Equatable {
    enum Kind { case incoming, outgoing }

    let user: IRCUser
    let message: String
    let kind: Kind
    let date: Date
}

/// Threading contract: every public method and property here is main-thread
/// only. `IRCConnection` always delivers its callbacks on the main queue
/// (see IRCConnection.swift), so every mutation of `users`/`messages`
/// already happens there; callers (`say`, `connect`, `disconnect`) are
/// expected to be UI code, which is main-thread by default in UIKit.
final class IRCClient {
    private static let host = "irc.hybridirc.com"
    private static let port = 7002
    private static let channelName = "#hayase-4e63ad915"
    /// Bytes per outgoing PRIVMSG line. Mirrors `message_max_length: 350`.
    private static let messageMaxLength = 350
    /// Mirrors `.slice(-150)` on the messages array.
    private static let historyLimit = 150
    /// Common channel-membership prefix symbols, stripped from NAMES
    /// entries. See the ISUPPORT/PREFIX scope note above.
    private static let namesPrefixSymbols: Set<Character> = ["~", "&", "@", "%", "+"]

    private(set) var users: [String: IRCUser] = [:]
    private(set) var messages: [IRCChatMessage] = []

    /// Called on the main thread whenever `users` changes.
    var onUsersChanged: (() -> Void)?
    /// Called on the main thread whenever `messages` changes.
    var onMessagesChanged: (() -> Void)?
    /// Mirrors the two-stage `MessageClient.new()` await: fires once after
    /// registration *and* our own channel join both complete.
    var onReady: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?

    private let identity: IRCIdentity
    private let connection = IRCConnection()

    private var didRegister = false
    private var didJoinChannel = false
    private var currentNick: String
    private var pendingNamesMembers: [IRCRawUser] = []

    init(identity: IRCIdentity) {
        self.identity = identity
        self.currentNick = Self.wireNick(for: identity)

        connection.onOpen = { [weak self] in self?.handleSocketOpen() }
        connection.onLine = { [weak self] line in self?.handleLine(line) }
        connection.onClose = { [weak self] error in self?.handleClose(error) }
    }

    func connect() {
        connection.connect(host: Self.host, port: Self.port)
    }

    /// Mirrors `MessageClient.destroy()`: `this.irc.connection?.end()` is
    /// called with no arguments, which — since `Connection.end(data,
    /// had_error)` only writes+waits when `data` is truthy — skips straight
    /// to closing the transport with no QUIT sent at all. An earlier version
    /// of this port sent an explicit `QUIT` first as an "improvement"; that
    /// was a real, disclosed-late divergence from upstream, not a Swift
    /// necessity, so it's removed here to match exactly.
    func disconnect() {
        connection.close()
    }

    /// Mirrors `MessageClient.say`. Splits on newlines first (a multi-line
    /// paste or a Shift+Enter'd message), then byte-chunks each resulting
    /// line so no single PRIVMSG exceeds `messageMaxLength`.
    func say(_ text: String) {
        guard didJoinChannel else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lines = trimmed.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .filter { !$0.isEmpty }
        for line in lines {
            for chunk in Self.chunk(line, maxBytes: Self.messageMaxLength) {
                connection.send(line: IRCMessage(command: "PRIVMSG", params: [Self.channelName, chunk]).serialized())
            }
        }

        appendMessage(IRCChatMessage(user: IRCUserMapping.chatUser(from: identity),
                                      message: trimmed, kind: .outgoing, date: Date()))
    }

    // MARK: - Identity → wire format
    // Mirrors the inline nick/username/gecos construction in
    // `MessageClient.new()`'s call to `client.irc.connect({...})`.

    private static func wireNick(for identity: IRCIdentity) -> String {
        // JS: `${ext[0]}${prefix}${pfpid}_${nick.replace('.', '')}`.
        // `ext[0]` on an empty string is `undefined` in JS, which stringifies
        // to "undefined" — preserved deliberately, see file header.
        let extLetter = identity.ext.first.map(String.init) ?? "undefined"
        let displayNick = replaceFirst(".", with: "", in: identity.nick)
        return "\(extLetter)\(identity.prefix)\(identity.pfpID)_\(displayNick)"
    }

    private static func wireUsername(for identity: IRCIdentity) -> String {
        "\(identity.type.rawValue)_\(identity.id)"
    }

    /// JS `String.replace(searchValue, replaceValue)` with a plain-string
    /// (non-regex, non-global) search only ever replaces the first match.
    private static func replaceFirst(_ target: Character, with replacement: String, in string: String) -> String {
        guard let index = string.firstIndex(of: target) else { return string }
        var result = string
        result.replaceSubrange(index...index, with: replacement)
        return result
    }

    // MARK: - Outgoing message chunking
    // A safe, grapheme-boundary-respecting stand-in for the reference's
    // `lineBreak`/grapheme-splitter-based chunking — not a byte-for-byte
    // port of that algorithm, but it achieves the same goal (never split a
    // multi-byte character or emoji across two PRIVMSGs) without pulling in
    // an equivalent dependency.
    private static func chunk(_ line: String, maxBytes: Int) -> [String] {
        guard line.utf8.count > maxBytes else { return [line] }
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for character in line {
            let charBytes = String(character).utf8.count
            if currentBytes + charBytes > maxBytes, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += charBytes
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Connection lifecycle

    private func handleSocketOpen() {
        // Mirrors `registerToNetwork()`: CAP LS + NICK + USER are all sent
        // immediately, without waiting for a reply to any of them.
        connection.send(line: IRCMessage(command: "CAP", params: ["LS", "302"]).serialized())
        connection.send(line: IRCMessage(command: "NICK", params: [currentNick]).serialized())
        connection.send(line: IRCMessage(command: "USER",
                                          params: [Self.wireUsername(for: identity), "0", "*", "https://hybridirc.com/"]).serialized())
    }

    private func handleClose(_ error: Error?) {
        didRegister = false
        didJoinChannel = false
        onDisconnected?(error)
    }

    private func handleLine(_ rawLine: String) {
        let message = IRCLineParser.parse(rawLine)
        switch message.command {
        case "CAP":
            handleCap(message)
        case "PING":
            // Mirrors `handler.connection.write('PONG ' + command.params[last])`
            // — only the final param is echoed back, not every param (matters
            // for the rare multi-param legacy PING form; a normal single-token
            // "PING :abc123" behaves identically either way).
            if let token = message.params.last {
                connection.send(line: IRCMessage(command: "PONG", params: [token]).serialized())
            }
        case "001": // RPL_WELCOME
            handleRegistered(message)
        case "353": // RPL_NAMEREPLY
            handleNamesReply(message)
        case "366": // RPL_ENDOFNAMES
            handleEndOfNames(message)
        case "JOIN":
            handleJoin(message)
        case "PART":
            removeUser(ident: message.ident)
        case "QUIT":
            removeUser(ident: message.ident)
        case "KICK":
            // See the file-header note: this intentionally removes the
            // kicker (message.ident), matching interface's own behavior,
            // not the person actually kicked.
            removeUser(ident: message.ident)
        case "PRIVMSG":
            handlePrivmsg(message)
        default:
            break
        }
    }

    /// Only these two capabilities are ever requested — see the file-header
    /// scope note for the full list the real library requests. Both were
    /// added after finding a real bug during validation, not as a style
    /// choice: without `userhost-in-names`, NAMES (353) replies contain bare
    /// nicks with no ident at all, and since `users` is keyed by ident (to
    /// match upstream, which also keys by ident), every member from the
    /// initial NAMES snapshot would collide on the same empty-string key —
    /// collapsing the whole channel's userlist down to whichever member was
    /// processed last. `multi-prefix` is requested alongside it since it's
    /// essentially free once any CAP REQ round-trip is already happening,
    /// and makes the NAMES prefix-stripping loop exercise its intended path
    /// instead of relying on servers sending single-prefix NAMES by default.
    private static let wantedCapabilities: Set<String> = ["userhost-in-names", "multi-prefix"]
    private var pendingCapRequest = false

    /// Handles only the CAP LS/ACK/NAK subcommands needed to request the two
    /// capabilities above (or skip straight to CAP END if the server offers
    /// neither) — not the full negotiation state machine the real library
    /// runs. See the file-header scope note.
    private func handleCap(_ message: IRCMessage) {
        guard message.params.count >= 2 else { return }
        switch message.params[1] {
        case "LS":
            let isFinalLine = message.params.count < 3 || message.params[2] != "*"
            guard isFinalLine else { return } // still waiting on a continuation line
            let offered = Set((message.params.last ?? "").split(separator: " ").map(String.init))
            let toRequest = Self.wantedCapabilities.intersection(offered)
            if toRequest.isEmpty {
                connection.send(line: IRCMessage(command: "CAP", params: ["END"]).serialized())
            } else {
                pendingCapRequest = true
                connection.send(line: IRCMessage(command: "CAP", params: ["REQ", toRequest.sorted().joined(separator: " ")]).serialized())
            }
        case "ACK", "NAK":
            // Whatever we asked for has been answered either way — end
            // negotiation. (No SASL is ever requested here, so there's no
            // further round-trip to wait for, unlike the full library.)
            guard pendingCapRequest else { return }
            pendingCapRequest = false
            connection.send(line: IRCMessage(command: "CAP", params: ["END"]).serialized())
        default:
            break
        }
    }

    private func handleRegistered(_ message: IRCMessage) {
        guard !didRegister else { return }
        didRegister = true
        // The library sets `this.user.nick` from RPL_WELCOME's own first
        // param on 'registered' — the server is authoritative here, not
        // whatever we originally requested (relevant if a nick were ever
        // truncated/mangled server-side; not handled specially, just no
        // longer silently wrong about what our own nick actually is).
        if let confirmedNick = message.params.first {
            currentNick = confirmedNick
        }
        connection.send(line: IRCMessage(command: "JOIN", params: [Self.channelName]).serialized())
    }

    private func handleJoin(_ message: IRCMessage) {
        guard message.params.first == Self.channelName else { return }
        if message.nick == currentNick, !didJoinChannel {
            didJoinChannel = true
            onReady?()
            return
        }
        // Someone else joining an already-open channel.
        let user = IRCUserMapping.chatUser(from: IRCRawUser(nick: message.nick, ident: message.ident))
        users[message.ident] = user
        onUsersChanged?()
    }

    private func handleNamesReply(_ message: IRCMessage) {
        // Mirrors the reference reading the channel from params[2]
        // specifically (not params[1] or the last param) and scoping its
        // names cache per-channel; we only ever join one channel, but this
        // still guards against acting on a NAMES reply for some other one.
        guard message.params.count > 2, message.params[2] == Self.channelName else { return }
        guard let memberList = message.params.last else { return }
        for rawMember in memberList.split(separator: " ") {
            var member = String(rawMember)
            while let first = member.first, Self.namesPrefixSymbols.contains(first) {
                member.removeFirst()
            }
            guard !member.isEmpty else { continue }
            let mask = IRCMask.parse(member)
            pendingNamesMembers.append(IRCRawUser(nick: mask.nick, ident: mask.user))
        }
    }

    private func handleEndOfNames(_ message: IRCMessage) {
        // Upstream reads the channel from params[1] for 366 (note: params[2]
        // for 353 above — different index, matching the reference exactly).
        guard message.params.count > 1, message.params[1] == Self.channelName else { return }
        for raw in pendingNamesMembers {
            users[raw.ident] = IRCUserMapping.chatUser(from: raw)
        }
        pendingNamesMembers.removeAll()
        onUsersChanged?()
    }

    private func removeUser(ident: String) {
        guard users.removeValue(forKey: ident) != nil else { return }
        onUsersChanged?()
    }

    private func handlePrivmsg(_ message: IRCMessage) {
        guard let rawText = message.params.last else { return }
        // CTCP (ACTION, VERSION, etc.) is wrapped in \x01...\x01 and is
        // deliberately not surfaced as a chat message — matching upstream,
        // where the library routes CTCP to separate 'action'/'ctcp request'
        // events that interface's MessageClient never subscribes to.
        // Mirrors `message.charAt(0) === '\x01' && message.charAt(message.length-1) === '\x01'`.
        // A single lone \x01 character satisfies both checks in JS too (same
        // character checked against itself at length 1), so it's dropped
        // here as well rather than displayed.
        if rawText.hasPrefix("\u{01}"), rawText.hasSuffix("\u{01}") {
            return
        }

        let sender = users[message.ident] ?? IRCUserMapping.chatUser(from: IRCRawUser(nick: message.nick, ident: message.ident))
        appendMessage(IRCChatMessage(user: sender, message: rawText, kind: .incoming, date: Date()))
    }

    private func appendMessage(_ message: IRCChatMessage) {
        messages.append(message)
        if messages.count > Self.historyLimit {
            messages.removeFirst(messages.count - Self.historyLimit)
        }
        onMessagesChanged?()
    }
}

extension IRCIdentity {
    /// Builds the identity Hayase presents to IRC: the signed-in AniList
    /// viewer's nick/id if available, otherwise a random guest. Mirrors the
    /// inline identity-construction logic in interface's `irc.svelte`.
    ///
    /// Important: whether someone is treated as `.anilist` vs `.guest`
    /// depends only on whether a viewer is signed in — NOT on whether they
    /// have an avatar set. JS's `if ($viewer?.viewer)` check only looks at
    /// the viewer itself; if the avatar URL happens to be empty, `extname`/
    /// `basename` on an empty string just produce more empty strings
    /// (`ext`/`base`/`pfpid`/`prefix` all become `''`), while `nick`/`id`
    /// still come from the real signed-in account. An earlier version of
    /// this method guarded on the avatar being non-empty and fell all the
    /// way back to a random guest identity when it wasn't — that discarded
    /// a real signed-in user's identity entirely instead of just showing
    /// them with a default avatar, which is what upstream actually does.
    static func current() -> IRCIdentity {
        guard let viewer = TrackerAccountManager.shared.viewer(for: .anilist) else {
            let nickSuffix = UUID().uuidString.prefix(6).lowercased()
            let guestID = UUID().uuidString.prefix(6).lowercased()
            return IRCIdentity(nick: "Guest-\(nickSuffix)", id: guestID, pfpID: "", prefix: "", ext: "", type: .guest)
        }

        let id = viewer.id
        let avatarURL = viewer.avatarURL ?? ""
        // Mirrors: ext = extname(url); base = basename(url, ext);
        //          pfpid = base.slice(id.length + 2)
        // On an empty/missing avatarURL these all naturally resolve to
        // empty strings too, same as the JS `path` calls would.
        let filename = (avatarURL as NSString).lastPathComponent
        let ext = (filename as NSString).pathExtension
        let base = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        let prefix = base.first.map(String.init) ?? ""
        let skip = id.count + 2
        let pfpID = base.count > skip ? String(base.dropFirst(skip)) : ""

        return IRCIdentity(nick: viewer.name, id: id, pfpID: pfpID, prefix: prefix, ext: ext, type: .anilist)
    }
}
