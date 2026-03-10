//
//  NativeBridge.swift — WKScriptMessageHandler bridging the Svelte webapp to native LibTorrent + MPV.
//
import UIKit
import WebKit

/// Handles all `window.webkit.messageHandlers.bridge.postMessage({...})` calls from the webapp.
/// Each call includes `{ id, action, payload }` — we resolve via
/// `window.__bridgeResolve(id, result)` or `window.__bridgeReject(id, error)`.
final class NativeBridge: NSObject, WKScriptMessageHandler {

    // Set by WebViewController after WKWebView is created.
    weak var webView: WKWebView?

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

        case "torrent_add":
            let link    = payload["link"]  as? String ?? ""
            let title   = payload["title"] as? String ?? ""
            let anilistID = payload["anilistID"] as? Int ?? 0
            torrentAdd(id: id, link: link, title: title, anilistID: anilistID)

        case "torrent_list":
            torrentList(id: id)

        case "torrent_pause":
            let hash = payload["hash"] as? String ?? ""
            torrentPause(id: id, hash: hash)

        case "torrent_resume":
            let hash = payload["hash"] as? String ?? ""
            torrentResume(id: id, hash: hash)

        case "torrent_delete":
            let hash        = payload["hash"]        as? String ?? ""
            let deleteFiles = payload["deleteFiles"]  as? Bool ?? false
            torrentDelete(id: id, hash: hash, deleteFiles: deleteFiles)

        case "torrent_files":
            let hash = payload["hash"] as? String ?? ""
            torrentFiles(id: id, hash: hash)

        case "player_open":
            let hash      = payload["hash"]      as? String ?? ""
            let fileIndex = payload["fileIndex"] as? Int    ?? 0
            let title     = payload["title"]     as? String ?? ""
            let anilistID = payload["anilistID"] as? Int    ?? 0
            let episode   = payload["episode"]   as? Int    ?? 1
            playerOpen(id: id, hash: hash, fileIndex: fileIndex,
                       title: title, anilistID: anilistID, episode: episode)

        case "progress_get":
            let hash      = payload["hash"]      as? String ?? ""
            let fileIndex = payload["fileIndex"] as? Int    ?? 0
            progressGet(id: id, hash: hash, fileIndex: fileIndex)

        default:
            reject(id: id, error: "Unknown action: \(action)")
        }
    }

    // MARK: - Torrent operations

    private func torrentAdd(id: String, link: String, title: String, anilistID: Int) {
        guard URL(string: link) != nil else {
            reject(id: id, error: "Invalid URL: \(link)"); return
        }
        let ts = TorrentService.sharedTorrentService
        DispatchQueue.main.async { [weak self] in
            let context = CoreDataService.sharedCoreDataService.mainQueueContext
            let fetchReq = NSFetchRequest<Torrents>(entityName: "Torrents")
            fetchReq.predicate = NSPredicate(format: "torrentTitle == %@", title)
            let existing = (try? context.fetch(fetchReq))?.first
            let entity: Torrents
            if let e = existing {
                entity = e
            } else {
                entity = NSEntityDescription.insertNewObject(forEntityName: "Torrents", into: context) as! Torrents
                entity.torrentTitle = title
                entity.torrentDownloadURL = link
                try? context.save()
            }
            ts.UpdateTorrentEntityInController(entity) { result in
                switch result {
                case .success(let handle):
                    let hex = handle.infoHashes.best.hex
                    self?.resolve(id: id, result: ["hash": hex])
                case .failure(let error):
                    self?.reject(id: id, error: error.localizedDescription)
                }
            }
        }
    }

    private func torrentList(id: String) {
        let ts = TorrentService.sharedTorrentService
        let list: [[String: Any]] = ts.handles.map { hex, handle in
            let snap = handle.snapshot
            return [
                "hash":         hex,
                "name":         snap.name,
                "progress":     snap.progress,
                "downloadRate": snap.downloadRate,
                "uploadRate":   snap.uploadRate,
                "isPaused":     snap.isPaused,
                "isFinished":   snap.isFinished,
                "isSeed":       snap.isSeed,
                "peers":        snap.numberOfPeers,
                "totalWanted":  snap.totalWanted,
                "totalDone":    snap.totalWantedDone,
                "state":        snap.state.rawValue,
            ]
        }
        resolve(id: id, result: list)
    }

    private func torrentPause(id: String, hash: String) {
        let ts = TorrentService.sharedTorrentService
        if let handle = ts.handles[hash] {
            handle.pause()
            resolve(id: id, result: true)
        } else {
            reject(id: id, error: "Torrent not found: \(hash)")
        }
    }

    private func torrentResume(id: String, hash: String) {
        let ts = TorrentService.sharedTorrentService
        if let handle = ts.handles[hash] {
            handle.resume()
            resolve(id: id, result: true)
        } else {
            reject(id: id, error: "Torrent not found: \(hash)")
        }
    }

    private func torrentDelete(id: String, hash: String, deleteFiles: Bool) {
        let ts = TorrentService.sharedTorrentService
        if let handle = ts.handles[hash] {
            ts.session.removeTorrent(handle, deleteFiles: deleteFiles)
            resolve(id: id, result: true)
        } else {
            reject(id: id, error: "Torrent not found: \(hash)")
        }
    }

    private func torrentFiles(id: String, hash: String) {
        let ts = TorrentService.sharedTorrentService
        guard let handle = ts.handles[hash] else {
            reject(id: id, error: "Torrent not found: \(hash)"); return
        }
        let snap = handle.snapshot
        let files: [[String: Any]] = snap.files.map { f in
            let progress: Double = f.size > 0 ? Double(f.downloaded) / Double(f.size) : 0
            return [
                "index":    f.index,
                "name":     f.name,
                "size":     f.size,
                "progress": progress,
                "path":     f.path,
            ]
        }
        resolve(id: id, result: files)
    }

    // MARK: - Player

    private func playerOpen(id: String, hash: String, fileIndex: Int,
                            title: String, anilistID: Int, episode: Int) {
        DispatchQueue.main.async { [weak self] in
            let ts = TorrentService.sharedTorrentService
            guard let handle = ts.handles[hash] else {
                self?.reject(id: id, error: "Torrent not found: \(hash)"); return
            }
            let snap = handle.snapshot
            guard snap.files.indices.contains(fileIndex) else {
                self?.reject(id: id, error: "File index \(fileIndex) out of range"); return
            }
            let fileEntry = snap.files[fileIndex]
            guard let path = fileEntry.path, !path.isEmpty else {
                self?.reject(id: id, error: "File has no path yet"); return
            }

            // Find the top-most view controller
            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                self?.reject(id: id, error: "No root view controller"); return
            }

            // Build a simple VideoEntity-compatible play call
            // We use VideoPlayerController which accepts a file URL
            let fileURL = URL(fileURLWithPath: path)
            let playerVC = VideoPlayerController()
            playerVC.videoURL  = fileURL
            playerVC.videoTitle = "\(title) — Ep \(episode)"
            playerVC.torrentHandle = handle
            playerVC.fileIndex = UInt(fileIndex)
            playerVC.anilistID = anilistID
            playerVC.episodeNumber = episode
            playerVC.modalPresentationStyle = .fullScreen
            rootVC.present(playerVC, animated: true)
            self?.resolve(id: id, result: true)
        }
    }

    // MARK: - Progress

    private func progressGet(id: String, hash: String, fileIndex: Int) {
        let ts = TorrentService.sharedTorrentService
        guard let handle = ts.handles[hash] else {
            resolve(id: id, result: ["progress": 0.0]); return
        }
        let snap = handle.snapshot
        if snap.files.indices.contains(fileIndex) {
            let f = snap.files[fileIndex]
            let progress: Double = f.size > 0 ? Double(f.downloaded) / Double(f.size) : Double(snap.progress)
            resolve(id: id, result: [
                "progress":     progress,
                "downloadRate": snap.downloadRate,
                "isFinished":   snap.isFinished || snap.isSeed,
            ])
        } else {
            resolve(id: id, result: ["progress": snap.progress])
        }
    }

    // MARK: - JS callbacks

    private func resolve(id: String, result: Any) {
        let json: String
        if let d = try? JSONSerialization.data(withJSONObject: result),
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
        let escaped = error.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.__bridgeReject('\(id)', '\(escaped)');"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js)
        }
    }
}
