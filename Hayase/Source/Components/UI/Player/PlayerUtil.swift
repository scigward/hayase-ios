//
//  PlayerUtil.swift
//  Hayase
//
//  Mirrors: src/lib/components/ui/player/util.ts: the screenshot of the player, which is copied and can be saved
//  from the toast that says so. (The other parts of util.ts are `MediaInfo`, which is the player's own state, and
//  the grouping of tracks by language that the options sheet does.)
//

import UIKit
import AVKit
import CoreMedia
import UniformTypeIdentifiers

extension VideoPlayerViewController {
    /// `screenshot` of util.ts: the frame is copied, and a toast says so with an action to have it as a file
    func captureScreenshot() {
        surface.mpv.captureScreenshotPNGData { [weak self] captured, failure in
            guard let self else { return }
            // when mpv cannot hand the frame over, what the surface shows (at the size of the screen) is the picture
            guard let data = captured ?? self.surfaceSnapshotPNG() else {
                // the interface downloads the file when it cannot copy it; there is no frame to give here
                AppErrorToast.show(failure ?? "", title: "Failed to copy screenshot to clipboard.", duration: 10)
                return
            }

            UIPasteboard.general.setData(data, forPasteboardType: "public.png")
            AppErrorToast.success("Saved screenshot to clipboard",
                                  description: "Click here to download it as a PNG file instead."
                                      + (captured == nil ? " (mpv: \(failure ?? "no answer"))" : ""),
                                  action: ToastAction(label: "Download") { [weak self] in
                                      self?.downloadScreenshot(data)
                                  })
        }
    }

    private func surfaceSnapshotPNG() -> Data? {
        guard surface.bounds.width > 0, surface.bounds.height > 0 else { return nil }
        let image = UIGraphicsImageRenderer(bounds: surface.bounds).image { _ in
            surface.drawHierarchy(in: surface.bounds, afterScreenUpdates: true)
        }
        return image.pngData()
    }

    /// `download()` of util.ts: the PNG as `screenshot_<time>.png`, which the share sheet puts in Files
    func downloadScreenshot(_ data: Data) {
        let name = "screenshot_\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppErrorToast.show(error.localizedDescription, title: "Failed to save file!")
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        (presentedViewController ?? self).present(activity, animated: true)
    }
}
