//
//  AniListReauth.swift
//  Hayase
//
//  Mirrors: interface lib/modules/anilist/urql-client.ts `authExchange`, whose `refreshAuth` runs
//  the AniList authorization again (`this.token()` then `this.auth(oauth)`) when a response says
//  "Invalid token", instead of signing the user out.
//

import UIKit
import AuthenticationServices

final class AniListReauth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AniListReauth()

    private var session: ASWebAuthenticationSession?
    private var waiters: [(Bool) -> Void] = []

    /// Every request that hit the invalid token waits for the one authorization that is open.
    func refresh(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [self] in
            waiters.append(completion)
            guard session == nil else { return }

            let authSession = ASWebAuthenticationSession(url: AniListAuth.authorizeURL, callbackURLScheme: "hayase") { [weak self] callbackURL, error in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.session = nil
                    var refreshed = false
                    if error == nil, let fragment = callbackURL?.fragment {
                        // hayase://#access_token=xxx&token_type=Bearer&expires_in=xxx
                        let params = fragment.components(separatedBy: "&")
                            .reduce(into: [String: String]()) { dict, pair in
                                let parts = pair.components(separatedBy: "=")
                                if parts.count == 2 { dict[parts[0]] = parts[1] }
                            }
                        if let token = params["access_token"] {
                            let expiresIn = params["expires_in"].flatMap(TimeInterval.init)
                            AniListAuth.completeLogin(token: token, expiresIn: expiresIn)
                            refreshed = true
                        }
                    }
                    let finished = self.waiters
                    self.waiters = []
                    finished.forEach { $0(refreshed) }
                }
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            self.session = authSession
            if !authSession.start() {
                self.session = nil
                let finished = waiters
                waiters = []
                finished.forEach { $0(false) }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        (UIApplication.shared.delegate as? AppDelegate)?.window ?? ASPresentationAnchor()
    }
}
