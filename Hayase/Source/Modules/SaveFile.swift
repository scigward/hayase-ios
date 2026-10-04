//
//  SaveFile.swift
//  Hayase
//
//  Mirrors: `saveFile` of src/lib/utils.ts: the data is offered as a file called `name.ext` (JSON with two spaces
//  of indent when it is not text), and is copied to the clipboard as well. On iOS a file is given with the share
//  sheet, whose "Save to Files" is the download of a browser.
//

import UIKit

enum SaveFile {
    /// `saveFile(data, name, ext)`. A failure is thrown: the caller says "Failed to save file!" with it.
    @MainActor
    static func save(_ data: Any, name: String, ext: String = "json",
                     presenter: UIViewController, sourceView: UIView) throws {
        let text: String
        if let string = data as? String {
            text = string
        } else {
            guard JSONSerialization.isValidJSONObject(data),
                  let encoded = JSONSerialization.safeData(data, options: [.prettyPrinted, .sortedKeys]) else {
                throw CocoaError(.coderInvalidValue)
            }
            text = String(decoding: encoded, as: UTF8.self)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
        try Data(text.utf8).write(to: url, options: .atomic)

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        presenter.present(activity, animated: true)
        // `return navigator.clipboard.writeText(data)`
        UIPasteboard.general.string = text
    }
}
