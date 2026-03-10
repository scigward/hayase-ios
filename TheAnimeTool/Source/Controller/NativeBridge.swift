//
//  NativeBridge.swift
//
//  WKScriptMessageHandler + WKUserScript injection that bridges the
//  scigward/interface Svelte webapp to native LibTorrent + MPVKit.
//
//  The interface repo's src/lib/modules/native.ts does:
//    export default Object.assign({ ...webFallbacks }, globalThis.native)
//  So we inject window.native via a WKUserScript before the page loads and
//  every method we define here overrides the web fallback automatically.
//
//  Each exposed method returns a Promise in JS land.  We resolve/reject them
//  via window.__bridgeResolve / window.__bridgeReject which are wired up by
//  the same injection script below.
//

import UIKit
import WebKit

// MARK: - NativeBridge

final class NativeBridge: NSObject, WKScriptMessageHandler {

    // Injected by WebViewController after WKWebView is created.
    weak var webView: WKWebView?

    // MARK: - WKUserScript (injected at document start)

    /// Returns the JavaScript that sets up window.__bridge* helpers and
    /// window.native with all Native interface methods.
    static func makeUserScript() -> WKUserScript {
        let js = """
(function () {
  'use strict';

  // ── Promise registry ────────────────────────────────────────────────────
  const _pending = {};

  window.__bridgeResolve = function (id, result) {
    const p = _pending[id];
    if (p) { delete _pending[id]; p.resolve(result); }
  };

  window.__bridgeReject = function (id, error) {
    const p = _pending[id];
    if (p) { delete _pending[id]; p.reject(new Error(error)); }
  };

  function _call(action, payload) {
    return new Promise(function (resolve, reject) {
      const id = Math.random().toString(36).slice(2) + Date.now();
      _pending[id] = { resolve, reject };
      window.webkit.messageHandlers.bridge.postMessage({ id, action, payload: payload || {} });
    });
  }

  // ── window.native — implements the hayase-app/native Native interface ───
  window.native = {
    isApp: true,

    // Torrent ──────────────────────────────────────────────────────────────
    playTorrent: function (torrent, mediaId, episode) {
      // torrent may be a magnet URI string or ArrayBuffer
      const isBuffer = torrent instanceof ArrayBuffer || ArrayBuffer.isView(torrent);
      let torrentStr;
      if (isBuffer) {
        const bytes = new Uint8Array(isBuffer ? torrent.buffer || torrent : torrent);
        torrentStr = btoa(String.fromCharCode(...bytes));
      } else {
        torrentStr = torrent;
      }
      return _call('playTorrent', { torrent: torrentStr, mediaId, episode, isBase64: !!isBuffer });
    },

    torrentInfo: function (id) {
      return _call('torrentInfo', { id });
    },

    fileInfo: function (id) {
      return _call('fileInfo', { id });
    },

    peerInfo: function (id) {
      return _call('peerInfo', { id });
    },

    protocolStatus: function (id) {
      return _call('protocolStatus', { id });
    },

    library: function () {
      return _call('library', {});
    },

    cachedTorrents: function () {
      return _call('cachedTorrents', {});
    },

    deleteTorrents: function (hash, deleteFiles) {
      return _call('deleteTorrents', { hash, deleteFiles: !!deleteFiles });
    },

    rescanTorrents: function () {
      return _call('rescanTorrents', {});
    },

    downloadProgress: function (progress) {
      return _call('downloadProgress', { progress });
    },

    createNZB: function (hash, nzb, domain, port, username, password, poolSize) {
      return _call('createNZB', { hash, nzb, domain, port, username, password, poolSize });
    },

    // Player ───────────────────────────────────────────────────────────────
    spawnPlayer: function (url, options) {
      return _call('spawnPlayer', { url, options: options || {} });
    },

    attachments: function (id) {
      return _call('attachments', { id });
    },

    tracks: function (id) {
      return _call('tracks', { id });
    },

    subtitles: function (id) {
      return _call('subtitles', { id });
    },

    chapters: function (id) {
      return _call('chapters', { id });
    },

    // AniList OAuth ────────────────────────────────────────────────────────
    authAL: function (url) {
      return _call('authAL', { url });
    },

    authMAL: function (url) {
      return _call('authMAL', { url });
    },

    // System ───────────────────────────────────────────────────────────────
    openURL: function (url) {
      return _call('openURL', { url });
    },

    version: function () {
      return _call('version', {});
    },

    getLogs: function () {
      return _call('getLogs', {});
    },

    getDeviceInfo: function () {
      return _call('getDeviceInfo', {});
    },

    checkAvailableSpace: function () {
      return _call('checkAvailableSpace', {});
    },

    checkIncomingConnections: function () {
      return _call('checkIncomingConnections', {});
    },

    // Media session (delegate to browser MediaSession API) ─────────────────
    setMediaSession: function (metadata) {
      if (typeof navigator !== 'undefined' && navigator.mediaSession) {
        navigator.mediaSession.metadata = new MediaMetadata({
          title: metadata.title,
          artist: metadata.description,
          artwork: [{ src: metadata.image }]
        });
      }
      return Promise.resolve();
    },

    setPositionState: function (state) {
      try { navigator.mediaSession.setPositionState(state); } catch (_) {}
      return Promise.resolve();
    },

    setPlayBackState: function (state) {
      try { navigator.mediaSession.playbackState = state; } catch (_) {}
      return Promise.resolve();
    },

    setActionHandler: function (action, handler) {
      try { navigator.mediaSession.setActionHandler(action, handler); } catch (_) {}
      return Promise.resolve();
    },

    // No-ops (desktop-only features) ───────────────────────────────────────
    restart:               function () { return Promise.resolve(); },
    minimise:              function () { return Promise.resolve(); },
    maximise:              function () { return Promise.resolve(); },
    focus:                 function () { return Promise.resolve(); },
    close:                 function () { return Promise.resolve(); },
    checkUpdate:           function () { return Promise.resolve(); },
    updateAndRestart:      function () { return Promise.resolve(); },
    updateReady:           function () { return new Promise(function () {}); },
    toggleDiscordDetails:  function () { return Promise.resolve(); },
    setHideToTray:         function () { return Promise.resolve(); },
    setExperimentalGPU:    function () { return Promise.resolve(); },
    transparency:          function () { return Promise.resolve(); },
    setZoom:               function () { return Promise.resolve(); },
    setAngle:              function () { return Promise.resolve(); },
    setDOH:                function () { return Promise.resolve(); },
    updateSettings:        function () { return Promise.resolve(); },
    openUIDevtools:        function () { return Promise.resolve(); },
    openTorrentDevtools:   function () { return Promise.resolve(); },
    debug:                 function () { return Promise.resolve(); },
    errors:                function () { return Promise.resolve(); },
    profile:               function () { return Promise.resolve(); },
    selectPlayer:          function () { return Promise.resolve('mpv'); },
    selectDownload:        function () { return Promise.resolve(''); },
    navigate:              function () { return Promise.resolve(); },
    updateProgress:        function () { return Promise.resolve(); },
    updatePeerCounts:      function () { return Promise.resolve([]); },
    getDisplays:           function () { return Promise.resolve(undefined); },
    castPlay:              function () { return Promise.resolve(); },
    castClose:             function () { return Promise.resolve(); },
    enableCORS:            function () { return Promise.resolve(); },
    updateToNewEndpoint:   function () { return Promise.resolve(); },
    defaultTransparency:   function () { return false; },
    share:                 function (opts) { return navigator.share ? navigator.share(opts) : Promise.resolve(); },
  };

  console.log('[NyaiS] window.native injected');
})();
"""
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "bridge",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let action = body["action"] as? String else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handle(id: id, action: action, payload: payload)
        }
    }

    // MARK: - Action dispatch

    private func handle(id: String, action: String, payload: [String: Any]) {
        switch action {

        // ── Torrent ──────────────────────────────────────────────────────
        case "playTorrent":
            let torrentStr = payload["torrent"] as? String ?? ""
            let mediaId    = payload["mediaId"]  as? Int    ?? 0
            let episode    = payload["episode"]  as? Int    ?? 1
            let isBase64   = payload["isBase64"] as? Bool   ?? false
            playTorrent(id: id, torrentStr: torrentStr, isBase64: isBase64,
                        mediaId: mediaId, episode: episode)

        case "torrentInfo":
            let hash = payload["id"] as? String ?? ""
            torrentInfo(id: id, hash: hash)

        case "fileInfo":
            let hash = payload["id"] as? String ?? ""
            fileInfo(id: id, hash: hash)

        case "peerInfo":
            let hash = payload["id"] as? String ?? ""
            peerInfo(id: id, hash: hash)

        case "protocolStatus":
            protocolStatus(id: id)

        case "library":
            library(id: id)

        case "cachedTorrents":
            cachedTorrents(id: id)

        case "deleteTorrents":
            let hash        = payload["hash"]        as? String ?? ""
            let deleteFiles = payload["deleteFiles"]  as? Bool   ?? false
            deleteTorrents(id: id, hash: hash, deleteFiles: deleteFiles)

        case "rescanTorrents":
            resolve(id: id, result: NSNull())

        case "downloadProgress":
            resolve(id: id, result: NSNull())

        // ── Player ───────────────────────────────────────────────────────
        case "spawnPlayer":
            let url        = payload["url"]     as? String ?? ""
            let options    = payload["options"]  as? [String: Any] ?? [:]
            spawnPlayer(id: id, url: url, options: options)

        case "attachments", "tracks", "subtitles", "chapters":
            resolve(id: id, result: [] as [Any])

        // ── Auth ─────────────────────────────────────────────────────────
        case "authAL":
            let url = payload["url"] as? String ?? ""
            authAL(id: id, url: url)

        case "authMAL":
            let url = payload["url"] as? String ?? ""
            authMAL(id: id, url: url)

        // ── System ───────────────────────────────────────────────────────
        case "openURL":
            let urlStr = payload["url"] as? String ?? ""
            DispatchQueue.main.async {
                if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
            }
            resolve(id: id, result: NSNull())

        case "version":
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            resolve(id: id, result: "v\(version)")

        case "getLogs":
            resolve(id: id, result: "")

        case "getDeviceInfo":
            resolve(id: id, result: [
                "platform": "ios",
                "model": UIDevice.current.model,
                "os": UIDevice.current.systemVersion,
            ])

        case "checkAvailableSpace":
            let free = (try? FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory())[.systemFreeSize] as? Int) ?? 0
            resolve(id: id, result: free)

        case "checkIncomingConnections":
            resolve(id: id, result: false)

        default:
            reject(id: id, error: "Unknown action: \(action)")
        }
    }

    // MARK: - Torrent implementations

    private func playTorrent(id: String, torrentStr: String, isBase64: Bool,
                             mediaId: Int, episode: Int) {
        let ts = TorrentService.sharedTorrentService
        DispatchQueue.main.async { [weak self] in
            let context = CoreDataService.sharedCoreDataService.mainQueueContext
            let fetchReq = NSFetchRequest<Torrents>(entityName: "Torrents")
            fetchReq.predicate = NSPredicate(format: "torrentDownloadURL == %@", torrentStr)
            let existing = (try? context.fetch(fetchReq))?.first
            let entity: Torrents
            if let e = existing {
                entity = e
            } else {
                entity = NSEntityDescription.insertNewObject(
                    forEntityName: "Torrents", into: context) as! Torrents
                entity.torrentDownloadURL = torrentStr
                entity.torrentTitle = torrentStr.hasPrefix("magnet:")
                    ? (torrentStr.components(separatedBy: "dn=").last?
                        .components(separatedBy: "&").first ?? torrentStr)
                    : torrentStr
                try? context.save()
            }
            ts.UpdateTorrentEntityInController(entity) { result in
                switch result {
                case .success(let handle):
                    // Return a TorrentFile-like array matching hayase-app/native TorrentFile
                    let snap = handle.snapshot
                    let files: [[String: Any]] = snap.files.enumerated().map { i, f in
                        return [
                            "name":  f.name ?? "",
                            "hash":  handle.infoHashes.best.hex,
                            "type":  "video/mkv",
                            "size":  f.size,
                            "path":  f.path ?? "",
                            "url":   "",
                            "lan":   "",
                            "id":    i,
                        ]
                    }
                    self?.resolve(id: id, result: files.isEmpty ? [
                        ["name": "", "hash": handle.infoHashes.best.hex,
                         "type": "video/mkv", "size": 0, "path": "",
                         "url": "", "lan": "", "id": 0]
                    ] : files)
                case .failure(let error):
                    self?.reject(id: id, error: error.localizedDescription)
                }
            }
        }
    }

    private func torrentInfo(id: String, hash: String) {
        let ts = TorrentService.sharedTorrentService
        guard let handle = ts.handles[hash] else {
            // Return default TorrentInfo matching hayase-app/native
            resolve(id: id, result: defaultTorrentInfo()); return
        }
        let snap = handle.snapshot
        resolve(id: id, result: [
            "name":     snap.name ?? "",
            "progress": snap.progress,
            "size":     ["total": snap.totalWanted, "downloaded": snap.totalWantedDone, "uploaded": 0],
            "speed":    ["down": snap.downloadRate, "up": snap.uploadRate],
            "time":     ["remaining": 0, "elapsed": 0],
            "peers":    ["seeders": snap.numberOfSeeds, "leechers": snap.numberOfPeers - snap.numberOfSeeds, "wires": snap.numberOfPeers],
            "pieces":   ["total": 0, "size": 0],
            "hash":     hash,
        ])
    }

    private func fileInfo(id: String, hash: String) {
        let ts = TorrentService.sharedTorrentService
        guard let handle = ts.handles[hash] else { resolve(id: id, result: [] as [Any]); return }
        let snap = handle.snapshot
        let files: [[String: Any]] = snap.files.enumerated().map { i, f in
            let prog: Double = f.size > 0 ? Double(f.downloaded) / Double(f.size) : 0
            return [
                "name":  f.name ?? "",
                "hash":  hash,
                "type":  "video/mkv",
                "size":  f.size,
                "path":  f.path ?? "",
                "url":   "",
                "lan":   "",
                "id":    i,
                // Extra: progress for UI
                "progress": prog,
            ]
        }
        resolve(id: id, result: files)
    }

    private func peerInfo(id: String, hash: String) {
        resolve(id: id, result: [] as [Any])
    }

    private func protocolStatus(id: String) {
        resolve(id: id, result: [
            "dht": false, "lsd": false, "pex": false,
            "nat": false, "forwarding": false,
            "persisting": false, "streaming": false,
        ])
    }

    private func library(id: String) {
        resolve(id: id, result: [] as [Any])
    }

    private func cachedTorrents(id: String) {
        resolve(id: id, result: [] as [Any])
    }

    private func deleteTorrents(id: String, hash: String, deleteFiles: Bool) {
        let ts = TorrentService.sharedTorrentService
        if let handle = ts.handles[hash] {
            ts.session.removeTorrent(handle, deleteFiles: deleteFiles)
        }
        resolve(id: id, result: NSNull())
    }

    // MARK: - Player

    private func spawnPlayer(id: String, url: String, options: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                self?.reject(id: id, error: "No root view controller"); return
            }
            let playerVC = VideoPlayerController()
            if let fileURL = URL(string: url) { playerVC.videoURL = fileURL }
            playerVC.videoTitle = options["title"] as? String ?? ""
            playerVC.modalPresentationStyle = .fullScreen
            rootVC.present(playerVC, animated: true)
            self?.resolve(id: id, result: NSNull())
        }
    }

    // MARK: - Auth (AniList OAuth via ASWebAuthenticationSession)

    private func authAL(id: String, url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let authURL = URL(string: url) else {
                self?.reject(id: id, error: "Invalid auth URL"); return
            }
            // Open in Safari — the app's redirect URI will be caught by the app
            UIApplication.shared.open(authURL, options: [:]) { _ in
                // The actual token delivery happens via deep link; for now resolve nil
                // so the UI doesn't hang. Full OAuth wiring is a follow-up.
                self?.reject(id: id, error: "OAuth not yet wired (open Safari)")
            }
        }
    }

    private func authMAL(id: String, url: String) {
        authAL(id: id, url: url) // Same pattern
    }

    // MARK: - Helpers

    private func defaultTorrentInfo() -> [String: Any] {
        return [
            "name": "", "progress": 0.0,
            "size":  ["total": 0, "downloaded": 0, "uploaded": 0],
            "speed": ["down": 0, "up": 0],
            "time":  ["remaining": 0, "elapsed": 0],
            "peers": ["seeders": 0, "leechers": 0, "wires": 0],
            "pieces": ["total": 0, "size": 0],
            "hash": "",
        ]
    }

    // MARK: - JS callbacks

    private func resolve(id: String, result: Any) {
        let json: String
        if result is NSNull {
            json = "null"
        } else if let d = try? JSONSerialization.data(withJSONObject: result),
                  let s = String(data: d, encoding: .utf8) {
            json = s
        } else if let b = result as? Bool {
            json = b ? "true" : "false"
        } else {
            json = "\"\(result)\""
        }
        let js = "window.__bridgeResolve('\(id)', \(json));"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js)
        }
    }

    private func reject(id: String, error: String) {
        let safe = error
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "window.__bridgeReject('\(id)', '\(safe)');"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js)
        }
    }
}

