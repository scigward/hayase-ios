//
//  DeepLink.swift
//  Hayase
//
//  Mirrors: what the interface does with `native.navigate({ target, value })`, which the host calls when a link
//  is opened (routes/+layout.svelte for `extensions`, routes/app/+layout.svelte for `schedule`, `anime`, `w2g`
//  and `debug`), and the links the interface itself makes: `https://hayase.watch/anime/<id>` (Share),
//  `https://hayase.watch/w2g/<code>` (the invite of a lobby), and the install route
//  `routes/app/extensions/install/[...url]`.
//
//  `hayase://anime/12`, `hayase://w2g/ab12cd34`, `hayase://schedule`, `hayase://debug` and
//  `hayase://extensions/install/https://…/index.json` (or `?url=`) all name the same targets as the https links
//  of hayase.watch do. Universal links need the associated-domains entitlement, which a build that is signed
//  again by the one who installs it cannot carry; the links arrive here when it is there.
//

import UIKit

enum DeepLink {
    enum Target: Equatable {
        case extensions(url: String)
        case schedule
        case anime(id: Int)
        case w2g(code: String)
        case debug
    }

    /// The pages that serve the web app: `WEB_URL` of lib/index.ts, and the address of the app itself.
    private static let hosts: Set<String> = ["hayase.watch", "www.hayase.watch", "hayase.app", "www.hayase.app"]

    /// A link that was opened before the app had a page to show it on (the splash, the setup).
    private static var pending: Target?

    // MARK: - Reading a link

    static func target(for url: URL) -> Target? {
        var segments: [String]
        switch url.scheme?.lowercased() {
        case "hayase":
            // hayase://anime/12: the first word is the host
            segments = ([url.host] + url.path.split(separator: "/").map { Optional(String($0)) }).compactMap { $0 }
        case "https", "http":
            guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
            segments = url.path.split(separator: "/").map(String.init)
        default:
            return nil
        }
        segments = segments.filter { !$0.isEmpty }
        if segments.first?.lowercased() == "app" { segments.removeFirst() }
        guard let head = segments.first?.lowercased() else { return nil }
        let rest = Array(segments.dropFirst())

        switch head {
        case "anime":
            guard let id = rest.first.flatMap({ Int($0) }) else { return nil }
            return .anime(id: id)
        case "w2g":
            guard let code = rest.first, !code.isEmpty else { return nil }
            return .w2g(code: code)
        case "schedule":
            return .schedule
        case "debug":
            return .debug
        case "extensions", "extension":
            // `new URL(value, 'http://localhost').searchParams.get('url') ?? value`
            if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value, !value.isEmpty {
                return .extensions(url: value)
            }
            var address = rest
            if address.first?.lowercased() == "install" { address.removeFirst() }
            // a link that was written with its slashes squeezed (`https:/…`) is put right by sanitizeExtensionUrl
            let value = address.joined(separator: "/")
            return value.isEmpty ? nil : .extensions(url: value)
        default:
            return nil
        }
    }

    // MARK: - Opening a link

    /// A link was opened with the app: it shows its page now, or as soon as the app has one.
    @MainActor
    static func open(_ url: URL) {
        guard let target = target(for: url) else { return }
        if isShellShown {
            perform(target)
        } else {
            pending = target
        }
    }

    /// The app has its pages: a link that was waiting for them is shown.
    @MainActor
    static func shellDidAppear() {
        guard let target = pending else { return }
        pending = nil
        perform(target)
    }

    @MainActor
    private static var isShellShown: Bool {
        (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController is HayaseSidebarController
    }

    @MainActor
    private static func perform(_ target: Target) {
        switch target {
        case .extensions(let url):
            // `native.navigate({ target: 'extensions', value })` of routes/+layout.svelte: the prompt, where the user is
            ExtensionInstallPrompt.show(url: url)
        case .schedule:
            Router.shared.navigate(.schedule)
        case .anime(let id):
            // `goto('/#/app/anime/<id>')`: the route loads the page
            Router.shared.navigate(.anime(id: id))
        case .w2g(let code):
            Router.shared.navigate(.w2g(id: code))
        case .debug:
            Router.shared.navigate(.debug)
        }
    }
}
