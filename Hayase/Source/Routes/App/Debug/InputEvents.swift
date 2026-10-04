//
//  InputEvents.swift
//  Hayase
//
//  Mirrors: the "Input Events" of src/routes/app/debug/+page.svelte: `handleEvent` keeps the latest event of each
//  constructor (Mouse, Keyboard, Pointer, Wheel, Touch) that the window sees, with the time, the type, the target, the
//  position, the button, the key and its code, the wheel's delta, the number of touches and the modifiers. The
//  window listens in the capture phase to everything; here it is a recognizer on the window that sees every touch
//  and the pointer's moves and scrolls, the presses of a hardware keyboard, and the keys that a controller sends.
//

import UIKit
import UIKit.UIGestureRecognizerSubclass

final class DebugInputEvents: NSObject, UIGestureRecognizerDelegate {
    /// One entry of `events`
    struct Event {
        var time: String
        var type: String
        var target: String
        var x: Double?
        var y: Double?
        var button: Int?
        var key: String?
        var code: String?
        var deltaY: Double?
        var touches: Int?
        var modifiers: String
    }

    /// The constructors of the interface's events, in the order of the page
    static let sources = ["Mouse", "Keyboard", "Pointer", "Wheel", "Touch"]

    /// `events`
    private(set) var events: [String: Event] = [:]
    /// The events changed
    var onChange: (() -> Void)?

    private weak var window: UIWindow?
    private var recognizers: [UIGestureRecognizer] = []
    private var lastScroll: CGFloat = 0
    private var lastKeyboard: (key: String, type: String, at: TimeInterval)?
    private let timeFormatter: DateFormatter = {
        // `new Date().toLocaleTimeString()`
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    // MARK: - Listening

    /// `window.addEventListener(type, handleEvent, { capture: true, ... })` for every type
    func start(in window: UIWindow) {
        guard recognizers.isEmpty else { return }
        self.window = window

        let touches = TouchObserver(target: nil, action: nil)
        touches.owner = self
        touches.delegate = self

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
        hover.delegate = self

        // the wheel: only what scrolls with a pointer, so that touch scrolling is not taken from anyone
        let wheel = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
        wheel.allowedTouchTypes = []
        wheel.allowedScrollTypesMask = .all
        wheel.cancelsTouchesInView = false
        wheel.delegate = self

        recognizers = [touches, hover, wheel]
        recognizers.forEach { window.addGestureRecognizer($0) }
        NotificationCenter.default.addObserver(self, selector: #selector(controllerKey(_:)),
                                               name: KeyboardEvent.didDispatch, object: nil)
    }

    func stop() {
        recognizers.forEach { window?.removeGestureRecognizer($0) }
        recognizers = []
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        stop()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: - Touches and the pointer

    private final class TouchObserver: UIGestureRecognizer {
        weak var owner: DebugInputEvents?

        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            owner?.touches(touches, phase: .began, event: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            owner?.touches(touches, phase: .moved, event: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            owner?.touches(touches, phase: .ended, event: event)
        }
    }

    private func touches(_ touches: Set<UITouch>, phase: UITouch.Phase, event: UIEvent) {
        for touch in touches {
            let point = touch.location(in: window)
            let target = describe(touch.view)
            let modifiers = modifiersText(event.modifierFlags)
            let active = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 1
            let isMouse = touch.type == .indirectPointer
            let button = isMouse && event.buttonMask.contains(.secondary) ? 2 : 0

            func pointer(_ type: String, button: Int = 0) {
                record("Pointer", type: type, target: target, point: point, button: button, modifiers: modifiers)
            }
            func mouse(_ type: String, button: Int = 0) {
                record("Mouse", type: type, target: target, point: point, button: button, modifiers: modifiers)
            }
            func touchEvent(_ type: String, count: Int) {
                record("Touch", type: type, target: target, touches: count, modifiers: modifiers)
            }

            switch phase {
            case .began:
                pointer("pointerdown", button: button)
                if isMouse {
                    mouse("mousedown", button: button)
                    if button == 2 { mouse("contextmenu", button: button) }
                } else {
                    touchEvent("touchstart", count: active)
                }
            case .moved:
                pointer("pointermove", button: -1)
                if isMouse { mouse("mousemove", button: -1) } else { touchEvent("touchmove", count: active) }
            case .ended:
                pointer("pointerup", button: button)
                if isMouse { mouse("mouseup", button: button) } else { touchEvent("touchend", count: max(0, active - 1)) }
                // a tap: the browser follows a touch with the events of a mouse, and a click
                if touch.tapCount > 0 {
                    if !isMouse {
                        mouse("mousemove", button: -1)
                        mouse("mousedown", button: 0)
                        mouse("mouseup", button: 0)
                    }
                    pointer("click", button: 0)
                    if touch.tapCount == 2 { mouse("dblclick", button: 0) }
                }
            default:
                break
            }
        }
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        let point = recognizer.location(in: window)
        let target = describe(recognizer.view?.hitTest(point, with: nil))
        record("Pointer", type: "pointermove", target: target, point: point, button: -1, modifiers: "none")
        record("Mouse", type: "mousemove", target: target, point: point, button: -1, modifiers: "none")
    }

    @objc private func scrolled(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: window).y
        defer { if recognizer.state == .ended || recognizer.state == .cancelled { lastScroll = 0 } else { lastScroll = translation } }
        guard recognizer.state == .changed || recognizer.state == .began else { return }
        let point = recognizer.location(in: window)
        // `deltaY` is positive when the content goes up, which a pan reports as a negative translation
        let delta = Double(lastScroll - translation)
        guard delta != 0 else { return }
        record("Wheel", type: "wheel", target: describe(window?.hitTest(point, with: nil)), point: point, button: 0,
               deltaY: delta, modifiers: modifiersText(recognizer.modifierFlags))
    }

    // MARK: - Keys

    /// A press of a hardware keyboard, which the page gives (`pressesBegan` and `pressesEnded`)
    func press(_ press: UIPress, isDown: Bool) {
        guard let key = press.key else { return }
        record(keyboard: Self.name(of: key), code: Self.code(of: key.keyCode), type: isDown ? "keydown" : "keyup",
               modifiers: modifiersText(key.modifierFlags))
    }

    /// The keys that a controller makes, which are dispatched as events of the window
    @objc private func controllerKey(_ notification: Notification) {
        guard let event = notification.object as? KeyboardEvent, event.isSynthetic else { return }
        let name: String
        switch event.key {
        case KeyboardEvent.Key.enter: name = "Enter"
        case KeyboardEvent.Key.escape: name = "Escape"
        case KeyboardEvent.Key.arrowUp: name = "ArrowUp"
        case KeyboardEvent.Key.arrowDown: name = "ArrowDown"
        case KeyboardEvent.Key.arrowLeft: name = "ArrowLeft"
        case KeyboardEvent.Key.arrowRight: name = "ArrowRight"
        default: name = event.key
        }
        record(keyboard: name, code: name, type: event.type == .keydown ? "keydown" : "keyup", modifiers: "none")
    }

    private func record(keyboard key: String, code: String, type: String, modifiers: String) {
        // a key that came by two ways (a key command and the press) is one event
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastKeyboard, last.key == key, last.type == type, now - last.at < 0.03 { return }
        lastKeyboard = (key, type, now)
        record("Keyboard", type: type, target: describe(UIResponder.currentFirstResponder as? UIView ?? window),
               key: key, code: code, modifiers: modifiers)
    }

    // MARK: - The record

    private func record(_ source: String, type: String, target: String, point: CGPoint? = nil, button: Int? = nil,
                        key: String? = nil, code: String? = nil, deltaY: Double? = nil, touches: Int? = nil,
                        modifiers: String) {
        events[source] = Event(time: timeFormatter.string(from: Date()), type: type, target: target,
                               x: point.map { Double($0.x.rounded()) }, y: point.map { Double($0.y.rounded()) },
                               button: button, key: key, code: code, deltaY: deltaY, touches: touches,
                               modifiers: modifiers)
        onChange?()
    }

    /// `elTarget`: the tag, the id and the classes of the element, which are the class and the identifier of the view
    private func describe(_ view: UIView?) -> String {
        guard let view else { return "null" }
        var text = String(describing: type(of: view))
        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty { text += "#" + identifier }
        return text
    }

    /// `[(ke.ctrlKey && 'Ctrl'), (ke.altKey && 'Alt'), (ke.shiftKey && 'Shift')].filter(e => e).join('+') || 'none'`
    private func modifiersText(_ flags: UIKeyModifierFlags) -> String {
        var names: [String] = []
        if flags.contains(.control) { names.append("Ctrl") }
        if flags.contains(.alternate) { names.append("Alt") }
        if flags.contains(.shift) { names.append("Shift") }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }

    // MARK: - key and code of a hardware key

    private static func name(of key: UIKey) -> String {
        switch key.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter: return "Enter"
        case .keyboardEscape: return "Escape"
        case .keyboardDeleteOrBackspace: return "Backspace"
        case .keyboardTab: return "Tab"
        case .keyboardSpacebar: return " "
        case .keyboardUpArrow: return "ArrowUp"
        case .keyboardDownArrow: return "ArrowDown"
        case .keyboardLeftArrow: return "ArrowLeft"
        case .keyboardRightArrow: return "ArrowRight"
        case .keyboardHome: return "Home"
        case .keyboardEnd: return "End"
        case .keyboardPageUp: return "PageUp"
        case .keyboardPageDown: return "PageDown"
        case .keyboardDeleteForward: return "Delete"
        case .keyboardCapsLock: return "CapsLock"
        case .keyboardLeftShift, .keyboardRightShift: return "Shift"
        case .keyboardLeftControl, .keyboardRightControl: return "Control"
        case .keyboardLeftAlt, .keyboardRightAlt: return "Alt"
        case .keyboardLeftGUI, .keyboardRightGUI: return "Meta"
        default:
            if (0x3A...0x45).contains(key.keyCode.rawValue) { return "F\(key.keyCode.rawValue - 0x39)" }
            return key.characters
        }
    }

    private static func code(of keyCode: UIKeyboardHIDUsage) -> String {
        let value = keyCode.rawValue
        switch value {
        case 0x04...0x1D: return "Key" + String(UnicodeScalar(UInt8(65 + value - 0x04)))
        case 0x1E...0x26: return "Digit\(value - 0x1D)"
        case 0x27: return "Digit0"
        case 0x28, 0x58: return value == 0x28 ? "Enter" : "NumpadEnter"
        case 0x29: return "Escape"
        case 0x2A: return "Backspace"
        case 0x2B: return "Tab"
        case 0x2C: return "Space"
        case 0x2D: return "Minus"
        case 0x2E: return "Equal"
        case 0x2F: return "BracketLeft"
        case 0x30: return "BracketRight"
        case 0x31: return "Backslash"
        case 0x33: return "Semicolon"
        case 0x34: return "Quote"
        case 0x35: return "Backquote"
        case 0x36: return "Comma"
        case 0x37: return "Period"
        case 0x38: return "Slash"
        case 0x39: return "CapsLock"
        case 0x3A...0x45: return "F\(value - 0x39)"
        case 0x4A: return "Home"
        case 0x4B: return "PageUp"
        case 0x4C: return "Delete"
        case 0x4D: return "End"
        case 0x4E: return "PageDown"
        case 0x4F: return "ArrowRight"
        case 0x50: return "ArrowLeft"
        case 0x51: return "ArrowDown"
        case 0x52: return "ArrowUp"
        case 0xE0: return "ControlLeft"
        case 0xE1: return "ShiftLeft"
        case 0xE2: return "AltLeft"
        case 0xE3: return "MetaLeft"
        case 0xE4: return "ControlRight"
        case 0xE5: return "ShiftRight"
        case 0xE6: return "AltRight"
        case 0xE7: return "MetaRight"
        default: return String(format: "Unidentified(0x%02X)", value)
        }
    }
}
