//
//  Gamepad.swift
//  Hayase
//
//  Mirrors: src/lib/modules/gamepad.ts: a game controller is a keyboard for the app. The A button is Enter,
//  B and Menu are Escape, and the D-pad and the left stick are the arrow keys, which repeat while they are
//  held (400ms to the first, then every 100ms). Each press is a `KeyboardEvent` that goes to the element that
//  has the focus and up through what contains it, as in the page, and then to `navigate` (an arrow moves the
//  focus) and the click of Enter on the focused element, which are what the browser leaves to gamepad.ts for
//  an event it did not make itself.
//
//  The interface reads a pad by its `standard` mapping, which is what GameController calls the extended
//  gamepad: a controller that has only a micro gamepad (a remote) is not used. It looks at the pad on every
//  frame, and only while the app is active (`activityState`, which on iOS is the app being active).
//

import UIKit
import GameController

// MARK: - Presses

/// The keys that a controller has: `BUTTON_MAP` and `STICK_MAP` of gamepad.ts
enum GamepadKey {
    case enter
    case escape
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
}

/// Which buttons are held and when they repeat: `pressed`, `handleButton` and `handleStickAxis` of gamepad.ts.
/// Times are in milliseconds.
struct GamepadPresses {
    enum Event: Equatable {
        case keydown(isRepeat: Bool)
        case keyup
    }

    /// Native keyboard repeat feel: ~400ms initial delay, then ~100ms per repeat
    static let initialRepeatDelay = 400.0
    static let repeatInterval = 100.0

    /// Left stick axes -> arrow directions, with hysteresis to avoid flicker
    static let stickPress = 0.5
    static let stickRelease = 0.3

    /// Buttons of the standard mapping, https://www.w3.org/TR/gamepad/#remapping, by their index
    static let buttonMap: [Int: GamepadKey] = [
        0: .enter,       // A / Cross
        1: .escape,      // B / Circle
        9: .escape,      // Start -> treat as back/menu for now
        12: .arrowUp,
        13: .arrowDown,
        14: .arrowLeft,
        15: .arrowRight,
    ]

    /// virtual button indices for left stick directions
    static let stickUp = 100
    static let stickDown = 101
    static let stickLeft = 102
    static let stickRight = 103

    static let stickMap: [Int: GamepadKey] = [
        stickUp: .arrowUp,
        stickDown: .arrowDown,
        stickLeft: .arrowLeft,
        stickRight: .arrowRight,
    ]

    /// the button index, and when it repeats next
    private var pressed: [Int: Double] = [:]

    static func key(for button: Int) -> GamepadKey? {
        buttonMap[button] ?? stickMap[button]
    }

    /// `handleButton`
    mutating func handleButton(_ id: Int, isDown: Bool, now: Double) -> Event? {
        if let nextRepeatAt = pressed[id] {
            if isDown {
                guard now >= nextRepeatAt else { return nil }
                pressed[id] = now + Self.repeatInterval
                return .keydown(isRepeat: true)
            }
            pressed[id] = nil
            return .keyup
        }
        guard isDown else { return nil }
        pressed[id] = now + Self.initialRepeatDelay
        return .keydown(isRepeat: false)
    }

    /// `handleStickAxis`: the two virtual buttons of an axis. It takes more to press than to hold.
    mutating func handleStickAxis(negative: Int, positive: Int, value: Double, now: Double) -> [(button: Int, event: Event)] {
        let negativeActive = pressed[negative] != nil ? value < -Self.stickRelease : value < -Self.stickPress
        let positiveActive = pressed[positive] != nil ? value > Self.stickRelease : value > Self.stickPress

        var events: [(button: Int, event: Event)] = []
        if let event = handleButton(negative, isDown: negativeActive, now: now) { events.append((negative, event)) }
        if let event = handleButton(positive, isDown: positiveActive, now: now) { events.append((positive, event)) }
        return events
    }

    /// One frame of a pad: `buttons` is whether each button of `buttonMap` is down, and `x` and `y` are the
    /// left stick (y is negative upwards, as in the standard mapping).
    mutating func update(buttons: [Int: Bool], x: Double, y: Double, now: Double) -> [(button: Int, event: Event)] {
        var events: [(button: Int, event: Event)] = []
        for button in Self.buttonMap.keys.sorted() {
            if let event = handleButton(button, isDown: buttons[button] ?? false, now: now) {
                events.append((button, event))
            }
        }

        // Skip axes if they look like non-centered device inputs (e.g. throttle, rudder).
        // Standard analog sticks return near 0 when at rest, flight-sim peripherals
        // often peg axes at -1/1 (throttle quadrant, pedals, etc.) causing constant
        // directional navigation.
        if abs(x) < 0.9 || abs(y) < 0.9 {
            events += handleStickAxis(negative: Self.stickLeft, positive: Self.stickRight, value: x, now: now)
            events += handleStickAxis(negative: Self.stickUp, positive: Self.stickDown, value: y, now: now)
        }
        return events
    }

    /// `stop`: what is still held is released, so no key is stuck down
    mutating func releaseAll() -> [Int] {
        let held = pressed.keys.sorted()
        pressed.removeAll()
        return held
    }
}

// MARK: - Gamepad

final class Gamepad: NSObject {
    static let shared = Gamepad()

    private var presses = GamepadPresses()
    private var displayLink: CADisplayLink?
    /// `pad`
    private var controller: GCController?
    /// `activityState.value === 'active'`
    private var isActive = false

    private override init() {
        super.init()
    }

    /// The end of gamepad.ts: it listens for pads and for the activity state, which starts the polling
    func start() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(updateActivePad), name: .GCControllerDidConnect, object: nil)
        center.addObserver(self, selector: #selector(updateActivePad), name: .GCControllerDidDisconnect, object: nil)
        center.addObserver(self, selector: #selector(activityChanged(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(activityChanged(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        isActive = UIApplication.shared.applicationState == .active
        updateActivePad()
    }

    @objc private func activityChanged(_ notification: Notification) {
        isActive = notification.name == UIApplication.didBecomeActiveNotification
        updateActivePad()
    }

    /// `updateActivePad`
    @objc private func updateActivePad() {
        controller = GCController.controllers().first { $0.extendedGamepad != nil }
        if controller != nil, isActive {
            startPolling()
        } else {
            stopPolling()
        }
    }

    // MARK: - requestAnimationFrame

    private func startPolling() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(poll))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopPolling() {
        guard let link = displayLink else { return }
        link.invalidate()
        displayLink = nil
        // release any buttons still marked as pressed to avoid stuck-key state
        for button in presses.releaseAll() { dispatch(.keyup, for: button) }
    }

    /// `start`: the pad as it is on this frame
    @objc private func poll() {
        guard let pad = controller?.extendedGamepad else { return }
        let buttons: [Int: Bool] = [
            0: pad.buttonA.isPressed,
            1: pad.buttonB.isPressed,
            9: pad.buttonMenu.isPressed,
            12: pad.dpad.up.isPressed,
            13: pad.dpad.down.isPressed,
            14: pad.dpad.left.isPressed,
            15: pad.dpad.right.isPressed,
        ]
        // `pad.axes`: X is positive to the right and Y positive downwards, where GameController's Y is up
        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = -Double(pad.leftThumbstick.yAxis.value)

        for (button, event) in presses.update(buttons: buttons, x: x, y: y, now: CACurrentMediaTime() * 1000) {
            dispatch(event, for: button)
        }
    }

    // MARK: - dispatch

    private func dispatch(_ event: GamepadPresses.Event, for button: Int) {
        guard let key = GamepadPresses.key(for: button) else { return }
        Navigate.inputType = .dpad
        // `target.dispatchEvent(new KeyboardEvent('keydown', ...))`: on the focused element, or else the body.
        // Nothing in the app listens for a key coming up (a key command runs when it goes down), so a `keyup` is
        // only seen by the Debug page.
        switch event {
        case .keydown(let isRepeat):
            KeyboardEvent(key: key.input, isRepeat: isRepeat, isSynthetic: true).dispatch()
        case .keyup:
            KeyboardEvent(type: .keyup, key: key.input, isSynthetic: true).dispatch()
        }
    }
}

private extension GamepadKey {
    /// `key` of the event, as a key command names it
    var input: String {
        switch self {
        case .enter: return KeyboardEvent.Key.enter
        case .escape: return KeyboardEvent.Key.escape
        case .arrowUp: return KeyboardEvent.Key.arrowUp
        case .arrowDown: return KeyboardEvent.Key.arrowDown
        case .arrowLeft: return KeyboardEvent.Key.arrowLeft
        case .arrowRight: return KeyboardEvent.Key.arrowRight
        }
    }
}
