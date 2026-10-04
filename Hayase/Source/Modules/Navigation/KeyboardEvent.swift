//
//  KeyboardEvent.swift
//  Hayase
//
//  Mirrors: the DOM's KeyboardEvent, and the way a `keydown` goes through the page, which the interface relies on
//  and gamepad.ts makes by hand for a controller. The event is dispatched on the focused element (or else the
//  body); every listener from there up gets it unless one stops it; the window's listener (`navigate`) is
//  the last; and what the browser does with a key that no listener prevented (Enter on the focused element is a
//  click) is done after that.
//
//  The listeners are the responders that are `KeyboardEventListener`s. A hardware keyboard reaches them through
//  UIKit's key commands: UIKit gives a key to the first responder that has a command for it, so each listener
//  also declares its keys with `UIKeyCommand.keydown`, and the command of every one of them does the same
//  thing, which is to dispatch the event from the focus. A controller dispatches it itself. Only the bubbling
//  phase has listeners in the app: the capture listeners of the interface (`stopAnimation`, the settings
//  grids that call `navigate` once) have nothing here to be before.
//

import UIKit
import GameController

// MARK: - Event

final class KeyboardEvent {
    /// `keydown` and `keyup`
    enum EventType {
        case keydown
        case keyup
    }

    /// An event is on its way: the Debug page shows the latest of each kind, as its listener of the window does.
    /// The object is the event.
    static let didDispatch = Notification.Name("KeyboardEvent.didDispatch")

    /// `key`, as a key command names it
    enum Key {
        static let enter = "\r"
        static let escape = UIKeyCommand.inputEscape
        static let arrowUp = UIKeyCommand.inputUpArrow
        static let arrowDown = UIKeyCommand.inputDownArrow
        static let arrowLeft = UIKeyCommand.inputLeftArrow
        static let arrowRight = UIKeyCommand.inputRightArrow
    }

    let type: EventType
    let key: String
    let modifierFlags: UIKeyModifierFlags
    /// `repeat`
    let isRepeat: Bool
    /// `!isTrusted`: the event was made by a controller and not by a keyboard
    let isSynthetic: Bool
    private(set) var defaultPrevented = false
    private(set) var propagationStopped = false

    init(type: EventType = .keydown, key: String, modifierFlags: UIKeyModifierFlags = [], isRepeat: Bool = false,
         isSynthetic: Bool = false) {
        self.type = type
        self.key = key
        self.modifierFlags = modifierFlags
        self.isRepeat = isRepeat
        self.isSynthetic = isSynthetic
    }

    func preventDefault() {
        defaultPrevented = true
    }

    func stopPropagation() {
        propagationStopped = true
    }

    /// The listeners the event goes to, in order, until one stops it
    func bubble(through listeners: [(KeyboardEvent) -> Void]) {
        for listener in listeners {
            if propagationStopped { return }
            listener(self)
        }
    }
}

// MARK: - Dispatch

/// A responder that listens for `keydown`: what `addEventListener('keydown', ...)` is on a node
protocol KeyboardEventListener: UIResponder {
    func keyDown(_ event: KeyboardEvent)
}

extension KeyboardEvent {
    /// `target.dispatchEvent(event)`, the target being the element that has the focus, or else the page
    func dispatch() {
        NotificationCenter.default.post(name: Self.didDispatch, object: self)
        guard type == .keydown, let container = Navigate.container else { return }
        let active = Navigate.liveActiveElement(in: container)

        var listeners: [(KeyboardEvent) -> Void] = []
        var responder: UIResponder? = Navigate.overlay(outside: container) ?? active ?? container
        while let current = responder {
            if let listener = current as? KeyboardEventListener { listeners.append(listener.keyDown) }
            responder = current.next
        }
        // `window.addEventListener('keydown', navigate)`
        listeners.append(Navigate.navigate)
        bubble(through: listeners)

        // Synthetic events have isTrusted=false, so the browser skips default activation behaviour; a keyboard's
        // Enter on a focused element is a click, and nothing prevented it
        if key == Key.enter, !defaultPrevented, let active { Navigate.click(active) }
    }
}

extension UIKeyCommand {
    /// A key command for a `KeyboardEventListener`: it is how UIKit comes to give the responder a key of a
    /// keyboard. `priority` is for a key that must not be left to the text field that has the keyboard.
    static func keydown(_ input: String, modifierFlags: UIKeyModifierFlags = [], priority: Bool = false) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: modifierFlags, action: #selector(UIResponder.dispatchKeyCommand(_:)))
        command.wantsPriorityOverSystemBehavior = priority
        return command
    }
}

extension UIResponder {
    /// The action of every `UIKeyCommand.keydown`: whichever responder UIKit found it on, the key is dispatched from the
    /// focus, as a DOM event is, and not from where UIKit was.
    @objc func dispatchKeyCommand(_ command: UIKeyCommand) {
        guard let key = command.input else { return }
        KeyboardEvent(key: key, modifierFlags: command.modifierFlags, isRepeat: HardwareKeys.isRepeat(key)).dispatch()
    }
}

// MARK: - repeat

/// A key command does not say that its key is held down. GameController does say when a key of a keyboard comes up, so a
/// key that has not come up since its last command is a repeat. The keys are the ones that `navigate` and the
/// controls take; without a keyboard that GameController knows, nothing is a repeat.
enum HardwareKeys {
    private static var lastHandled: [String: TimeInterval] = [:]
    /// A key that is held repeats within this time; one that has no word of its release stops being a repeat after it
    private static let heldFor: TimeInterval = 1.5

    private static let codes: [GCKeyCode: String] = [
        .upArrow: KeyboardEvent.Key.arrowUp,
        .downArrow: KeyboardEvent.Key.arrowDown,
        .leftArrow: KeyboardEvent.Key.arrowLeft,
        .rightArrow: KeyboardEvent.Key.arrowRight,
        .returnOrEnter: KeyboardEvent.Key.enter,
        .escape: KeyboardEvent.Key.escape,
    ]

    static func start() {
        let center = NotificationCenter.default
        center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { _ in attach() }
        center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { _ in lastHandled = [:] }
        attach()
    }

    private static func attach() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { _, _, keyCode, isPressed in
            guard !isPressed, let key = codes[keyCode] else { return }
            if Thread.isMainThread {
                lastHandled[key] = nil
            } else {
                DispatchQueue.main.async { lastHandled[key] = nil }
            }
        }
    }

    /// Whether this is the key that is held down again, and the key is now one that was handled
    static func isRepeat(_ key: String) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        defer { if codes.values.contains(key) { lastHandled[key] = now } }
        guard let last = lastHandled[key] else { return false }
        return now - last < heldFor
    }
}

// MARK: - First responder

private weak var foundFirstResponder: UIResponder?

extension UIResponder {
    /// The responder that has the keyboard, which UIKit only gives to the one that asks for it: an action sent to
    /// no one in particular goes to the first responder.
    static var currentFirstResponder: UIResponder? {
        foundFirstResponder = nil
        UIApplication.shared.sendAction(#selector(UIResponder.captureFirstResponder), to: nil, from: nil, for: nil)
        return foundFirstResponder
    }

    @objc fileprivate func captureFirstResponder() {
        foundFirstResponder = self
    }
}
