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
        if let viewer = viewer, let data = try? JSONEncoder().encode(viewer) {
            UserDefaults.standard.set(data, forKey: tracker.viewerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tracker.viewerKey)
        }
        notify()
    }

    // MARK: - Token

    func token(for tracker: TrackerKind) -> String? {
        UserDefaults.standard.string(forKey: tracker.tokenKey)
    }

    func setToken(_ token: String?, for tracker: TrackerKind) {
        if let token = token {
            UserDefaults.standard.set(token, forKey: tracker.tokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tracker.tokenKey)
        }
    }

    // MARK: - Login state

    func isLoggedIn(_ tracker: TrackerKind) -> Bool {
        if tracker == .local { return true }
        return viewer(for: tracker) != nil
    }

    // MARK: - Logout

    func logout(_ tracker: TrackerKind) {
        setViewer(nil, for: tracker)
        setToken(nil, for: tracker)
        if tracker == .anilist {
            AniListClient.shared.clearViewerDependentCaches()
            AniListTracking.shared.clearViewerCache()
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
