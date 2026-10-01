// Mirrors: src/routes/app/settings/accounts/+page.svelte (authentication controls)
import UIKit
import AuthenticationServices

extension HayaseAccountCardView {
    private static func reportLoginError(_ error: Error?) {
        guard let error else { return }
        if let nativeError = error as? ASWebAuthenticationSessionError,
           nativeError.code == .canceledLogin { return }
        AppErrorToast.show(error.localizedDescription, title: "Login failed!")
    }
    // MARK: - AniList Login


    func loginAniList() {
        guard let vc = parentVC else { return }
        let url = AniListAuth.authorizeURL

        // ASWebAuthenticationSession properly handles custom URL scheme redirects
        // (SFSafariViewController cannot navigate to custom schemes like hayase://).
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "hayase"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async { [weak self] in
                self?.authSession = nil
                self?.authPresentationContext = nil
                Self.reportLoginError(error)
                guard let callbackURL = callbackURL, error == nil else { return }

                // AniList implicit grant puts the token in the URL fragment:
                //   hayase://#access_token=xxx&token_type=Bearer&expires_in=xxx
                if let fragment = callbackURL.fragment {
                    let params = fragment.components(separatedBy: "&")
                        .reduce(into: [String: String]()) { dict, pair in
                            let parts = pair.components(separatedBy: "=")
                            if parts.count == 2 { dict[parts[0]] = parts[1] }
                        }
                    if let token = params["access_token"] {
                        let expiresIn = params["expires_in"].flatMap(TimeInterval.init)
                        AniListAuth.completeLogin(token: token, expiresIn: expiresIn)
                    }
                }
            }
        }
        let ctx = AniListAuthPresentationContext(anchor: vc)
        authPresentationContext = ctx
        session.presentationContextProvider = ctx
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - Kitsu Login

    func loginKitsu() {
        guard let vc = parentVC else { return }
        let dialog = SettingsDialogViewController(title: "Kitsu Login")
        let email = SettingsInputControl(value: "", placeholder: "email@website.com", width: 440)
        email.input.keyboardType = .emailAddress
        let password = SettingsInputControl(value: "", placeholder: "**************", width: 440, secure: true)
        for (title, input) in [("Login", email), ("Password", password)] {
            let row = UIStackView(arrangedSubviews: [SettingsTypography.label(title, size: 14, lineHeight: 20, weight: .bold), input])
            row.axis = .vertical
            row.spacing = 8
            dialog.content.addArrangedSubview(row)
        }
        dialog.content.addArrangedSubview(SettingsTypography.label(
            "Your password is not stored in the app, it is sent directly to Kitsu for authentication.",
            size: 14, lineHeight: 20, color: UIColor.HayaseTheme.mutedForeground))
        let login = SettingsTypography.button("Login")
        login.addAction(UIAction { [weak email, weak password] _ in
            // `ksclient.login(kitsuLogin, kitsuPassword)`: the dialog stays, only Cancel closes it
            KitsuAuth.login(email: email?.input.text ?? "", password: password?.input.text ?? "") { _ in }
        }, for: .touchUpInside)
        let cancel = SettingsTypography.button("Cancel", destructive: true)
        cancel.addAction(UIAction { [weak dialog] _ in dialog?.close() }, for: .touchUpInside)
        dialog.content.addArrangedSubview(login)
        dialog.content.addArrangedSubview(cancel)
        vc.present(dialog, animated: false)
    }

    // MARK: - MAL Login

    func loginMAL() {
        guard let vc = parentVC else { return }
        let codeVerifier = MALAuth.generateCodeVerifier()
        let url = MALAuth.authorizeURL(codeChallenge: codeVerifier)

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "hayase"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async { [weak self] in
                self?.authSession = nil
                self?.authPresentationContext = nil
                Self.reportLoginError(error)
                guard let callbackURL = callbackURL, error == nil else { return }

                // MAL PKCE flow returns the code in the query string:
                //   hayase://callback?code=xxx
                if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    MALAuth.completeLogin(code: code, codeVerifier: codeVerifier)
                }
            }
        }
        let ctx = AniListAuthPresentationContext(anchor: vc)
        authPresentationContext = ctx
        session.presentationContextProvider = ctx
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    // MARK: - Simkl Login

    func loginSimkl() {
        guard let vc = parentVC else { return }
        guard !SimklAuth.clientID.isEmpty, !SimklAuth.clientSecret.isEmpty else {
            TrackerToast.error("Simkl Sync", "Simkl Client ID and Client Secret must be configured in Simkl settings.")
            return
        }
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let url = SimklAuth.authorizeURL(state: state) else { return }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "hayase") { [weak self] callbackURL, error in
            DispatchQueue.main.async { [weak self] in
                self?.authSession = nil
                self?.authPresentationContext = nil
                Self.reportLoginError(error)
                guard error == nil,
                      let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      components.queryItems?.first(where: { $0.name == "state" })?.value == state,
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }
                // The provider reports the original API error once, as on the web.
                SimklAuth.completeLogin(code: code) { _ in }
            }
        }
        let context = AniListAuthPresentationContext(anchor: vc)
        authPresentationContext = context
        session.presentationContextProvider = context
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }


}

/// Provides the presentation anchor window for ASWebAuthenticationSession.
final class AniListAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var anchor: UIViewController?

    init(anchor: UIViewController) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor?.view.window ?? UIApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
