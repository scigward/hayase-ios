//
//  Client.swift
//  Hayase
//
//  Auth aggregator — manages multiple authentication providers.
//  Mirrors: src/lib/modules/auth/client.ts
//

import Foundation

// MARK: - TrackerAccountManager

final class TrackerAccountManager {

    static let shared = TrackerAccountManager()

    static let didChange = Notification.Name("TrackerAccountManagerDidChange")

    private init() {}

    // MARK: - Sync toggles

    func isSyncEnabled(for tracker: TrackerKind) -> Bool {
        return UserDefaults.standard.object(forKey: tracker.syncKey) as? Bool ?? true
    }

    func setSyncEnabled(_ enabled: Bool, for tracker: TrackerKind) {
        UserDefaults.standard.set(enabled, forKey: tracker.syncKey)
        notify()
    }

    // MARK: - Viewer info

    func viewer(for tracker: TrackerKind) -> TrackerViewer? {
        guard let data = UserDefaults.standard.data(forKey: tracker.viewerKey) else { return nil }
        return try? JSONDecoder().decode(TrackerViewer.self, from: data)
    }

    func setViewer(_ viewer: TrackerViewer?, for tracker: TrackerKind) {
        let previousViewer = self.viewer(for: tracker)
        if let viewer = viewer, let data = try? JSONEncoder().encode(viewer) {
            UserDefaults.standard.set(data, forKey: tracker.viewerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tracker.viewerKey)
        }
        if tracker == .anilist, previousViewer?.id != viewer?.id {
            clearAniListRuntimeState()
        }
        notify()
    }

    // MARK: - Token

    func token(for tracker: TrackerKind) -> String? {
        // AniList does not sign out on an old token: `refreshAuth` runs the authorization again
        guard tracker == .anilist || !isTokenExpired(for: tracker) else {
            expireSession(for: tracker)
            return nil
        }
        return Keychain.string(forKey: tracker.tokenKey)
    }

    func tokenExpiryDate(for tracker: TrackerKind) -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: tracker.tokenExpiryKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    func isTokenExpired(for tracker: TrackerKind, now: Date = Date()) -> Bool {
        guard let expiry = tokenExpiryDate(for: tracker) else { return false }
        return expiry.timeIntervalSince(now) <= 0
    }

    func setToken(_ token: String?, for tracker: TrackerKind, expiresAt: Date? = nil) {
        if let token = token {
            Keychain.set(token, forKey: tracker.tokenKey)
            if let expiresAt {
                UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: tracker.tokenExpiryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tracker.tokenExpiryKey)
            }
        } else {
            Keychain.set(nil, forKey: tracker.tokenKey)
            UserDefaults.standard.removeObject(forKey: tracker.tokenExpiryKey)
        }
    }

    private func expireSession(for tracker: TrackerKind) {
        setViewer(nil, for: tracker)
        setToken(nil, for: tracker)
        if tracker == .anilist {
            clearAniListRuntimeState()
        }
        notify()
    }

    func clearAniListSessionForAuthFailure() {
        setViewer(nil, for: .anilist)
        setToken(nil, for: .anilist)
        clearAniListRuntimeState()
        notify()
    }

    private func clearAniListRuntimeState() {
        AniListClient.shared.clearViewerDependentCaches()
        AniListTracking.shared.clearViewerCache()
        AniListOperationCache.shared.clearViewerScopedEntries()
        DispatchQueue.main.async {
            Router.shared.clearAniListViewerState()
        }
    }

    // MARK: - Login state

    func isLoggedIn(_ tracker: TrackerKind) -> Bool {
        if tracker == .local { return true }
        if tracker == .anilist || tracker == .simkl {
            return viewer(for: tracker) != nil && token(for: tracker) != nil
        }
        return viewer(for: tracker) != nil
    }

    // MARK: - Logout

    func logout(_ tracker: TrackerKind) {
        if tracker == .anilist {
            AniListRequestExecutor.shared.cancelAll()
        }
        setViewer(nil, for: tracker)
        setToken(nil, for: tracker)
        if tracker == .anilist {
            clearAniListRuntimeState()
        }
        notify()
    }

    // MARK: - Notify

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}
