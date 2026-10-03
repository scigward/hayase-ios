//
//  SetupChecks.swift
//  Hayase
//
//  Mirrors: the `Checks` of src/routes/setup/Footer.svelte
//
//    promise: Promise<{ status: 'warning' | 'success' | 'error', text: string, slot?: string }>
//    title: string
//    pending: string
//

import Foundation

/// A check of the footer, which is pending until it is resolved. Like a promise it settles once:
/// the first result is the one it keeps.
final class SetupCheck {
    enum Status {
        case warning
        case success
        case error
    }

    struct Result {
        let status: Status
        let text: String
        /// The page's own content shown after the text (`slot`).
        var slot: String?

        init(status: Status, text: String, slot: String? = nil) {
            self.status = status
            self.text = text
            self.slot = slot
        }
    }

    let title: String
    let pending: String
    private(set) var result: Result?
    private var observers: [() -> Void] = []

    init(title: String, pending: String) {
        self.title = title
        self.pending = pending
    }

    var isSettled: Bool { result != nil }

    /// `resolve(...)`; callable from any thread. Observers hear of it on the main one.
    func resolve(_ result: Result) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.resolve(result) }
            return
        }
        guard self.result == nil else { return }
        self.result = result
        let observers = self.observers
        self.observers = []
        observers.forEach { $0() }
    }

    /// `promise.then(...)`: runs at once, on the main thread, when the check has settled already.
    func onSettle(_ observer: @escaping () -> Void) {
        if result != nil {
            observer()
        } else {
            observers.append(observer)
        }
    }
}
