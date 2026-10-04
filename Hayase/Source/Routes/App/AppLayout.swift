//
//  AppLayout.swift
//  Hayase
//
//  Mirrors: src/routes/app/+layout.svelte: what the app does with what is pasted into it or dropped on it (`handleTransfer`):
//  an image is searched for with trace.moe, and a link to an image or to a Watch Together lobby is opened.
//

import UIKit

extension HayaseSidebarController {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponder.paste(_:)) {
            let board = UIPasteboard.general
            return board.hasImages || board.hasStrings || board.hasURLs
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if let image = board.image {
            handleTransferred(image: image)
        } else if let text = board.string ?? board.url?.absoluteString {
            handleTransferred(text: text)
        }
    }

    static let imagePattern = try? NSRegularExpression(pattern: "\\.(jpeg|jpg|gif|png|webp)", options: .caseInsensitive)

    static let w2gPattern = try? NSRegularExpression(pattern: "hayase\\.watch//w2g/(.+)")

    /// A picture goes to the search page to be looked up.
    func handleTransferred(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        openSearchToTrace(.image(data, mimeType: "image/jpeg"))
    }

    /// Text that names a picture goes to the search page too; a watch together link opens its room.
    func handleTransferred(text: String) {
        let whole = NSRange(text.startIndex..., in: text)
        if Self.imagePattern?.firstMatch(in: text, range: whole) != nil {
            openSearchToTrace(.url(text))
        } else if let match = Self.w2gPattern?.firstMatch(in: text, range: whole),
                  let range = Range(match.range(at: 1), in: text) {
            router.navigate(.w2g(id: String(text[range])))
        }
    }

    /// `goto('/#/app/search', { state: { image } })`
    func openSearchToTrace(_ source: TraceMoe.Source) {
        router.navigate(.search(nil))
        let navigation = hostNavigationController(for: .search(nil))
        (navigation?.viewControllers.first as? SearchViewController)?.trace(source)
    }
}

extension HayaseSidebarController: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.canLoadObjects(ofClass: UIImage.self)
            || session.canLoadObjects(ofClass: URL.self)
            || session.canLoadObjects(ofClass: NSString.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        if session.canLoadObjects(ofClass: UIImage.self) {
            _ = session.loadObjects(ofClass: UIImage.self) { [weak self] (objects: [NSItemProviderReading]) in
                guard let image = objects.first as? UIImage else { return }
                DispatchQueue.main.async { self?.handleTransferred(image: image) }
            }
        } else if session.canLoadObjects(ofClass: NSString.self) {
            _ = session.loadObjects(ofClass: NSString.self) { [weak self] (objects: [NSItemProviderReading]) in
                guard let text = objects.first as? String else { return }
                DispatchQueue.main.async { self?.handleTransferred(text: text) }
            }
        } else {
            _ = session.loadObjects(ofClass: URL.self) { [weak self] urls in
                guard let url = urls.first else { return }
                DispatchQueue.main.async { self?.handleTransferred(text: url.absoluteString) }
            }
        }
    }
}
