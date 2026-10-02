// Mirrors player.svelte loadWithDefaults and keybinds.svelte's saved key-to-action map.
import UIKit

enum PlayerKeyBindings {
    struct Binding {
        let code: String
        let id: String
        let icon: String?
        let description: String
    }
    static let defaults: [Binding] = [
        Binding(code: "KeyX", id: "screenshot_monitor", icon: "screen-share", description: "Save Screenshot to Clipboard"),
        Binding(code: "KeyI", id: "list", icon: "list", description: "Toggle Stats"),
        Binding(code: "Space", id: "play_arrow", icon: "play", description: "Play/Pause"),
        Binding(code: "KeyN", id: "skip_next", icon: "skip-forward", description: "Next Episode"),
        Binding(code: "KeyB", id: "skip_previous", icon: "skip-back", description: "Previous Episode"),
        Binding(code: "KeyA", id: "deblur", icon: "contrast", description: "Toggle Video Debanding"),
        Binding(code: "KeyM", id: "volume_off", icon: "volume-x", description: "Toggle Mute"),
        Binding(code: "KeyP", id: "picture_in_picture", icon: "picture-in-picture-2", description: "Toggle Picture in Picture"),
        Binding(code: "KeyF", id: "fullscreen", icon: "maximize", description: "Toggle Fullscreen"),
        Binding(code: "KeyS", id: "+90", icon: nil, description: "Skip Intro/90s"),
        Binding(code: "KeyW", id: "fit_width", icon: "proportions", description: "Toggle Video Cover"),
        Binding(code: "KeyD", id: "cast", icon: "cast", description: "Cast"),
        Binding(code: "KeyC", id: "subtitles", icon: "captions", description: "Cycle Subtitles"),
        Binding(code: "ArrowLeft", id: "fast_rewind", icon: "rewind", description: "Rewind"),
        Binding(code: "ArrowRight", id: "fast_forward", icon: "fast-forward", description: "Seek"),
        Binding(code: "ArrowUp", id: "volume_up", icon: "volume-2", description: "Volume Up"),
        Binding(code: "ArrowDown", id: "volume_down", icon: "volume-1", description: "Volume Down"),
        Binding(code: "BracketLeft", id: "history", icon: "rotate-ccw", description: "Decrease Playback Rate"),
        Binding(code: "BracketRight", id: "update", icon: "rotate-cw", description: "Increase Playback Rate"),
        Binding(code: "Backslash", id: "schedule", icon: "refresh-ccw", description: "Reset Playback Rate"),
        Binding(code: "Semicolon", id: "subtitle_delay_minus", icon: "decimals-arrow-left", description: "Decrease Subtitle Delay"),
        Binding(code: "Quote", id: "subtitle_delay_plus", icon: "decimals-arrow-right", description: "Increase Subtitle Delay"),
    ]
    private static let storageKey = "playerKeyBindings"
    static var mapping: [String: String] {
        guard let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] else {
            return Dictionary(uniqueKeysWithValues: defaults.map { ($0.code, $0.id) })
        }
        let valid = Set(defaults.map { $0.id })
        var result = saved.filter { valid.contains($0.value) }
        let existing = Set(result.values)
        for binding in defaults where !existing.contains(binding.id) && result[binding.code] == nil {
            result[binding.code] = binding.id
        }
        return result
    }
    static func binding(for code: String) -> Binding? {
        guard let id = mapping[code] else { return nil }
        return defaults.first { $0.id == id }
    }
    static func move(from source: String, to destination: String) {
        guard source != destination else { return }
        var map = mapping
        let sourceBind = map[source]
        map[source] = map[destination]
        map[destination] = sourceBind
        UserDefaults.standard.set(map, forKey: storageKey)
    }
    /// A key command with an empty input raises, so a code that names no key has no input.
    static func input(for code: String) -> String? {
        rawInput(for: code).flatMap { $0.isEmpty ? nil : $0 }
    }
    private static func rawInput(for code: String) -> String? {
        if code.hasPrefix("Key") { return String(code.dropFirst(3)).lowercased() }
        if code.hasPrefix("Digit") { return String(code.dropFirst(5)) }
        return ["Space": " ", "ArrowLeft": UIKeyCommand.inputLeftArrow,
                "ArrowRight": UIKeyCommand.inputRightArrow, "ArrowUp": UIKeyCommand.inputUpArrow,
                "ArrowDown": UIKeyCommand.inputDownArrow, "BracketLeft": "[", "BracketRight": "]",
                "Backslash": "\\", "Semicolon": ";", "Quote": "'", "Minus": "-", "Equal": "=",
                "Comma": ",", "Period": ".", "Slash": "/", "Escape": UIKeyCommand.inputEscape,
                "Tab": "\t", "Enter": "\r", "Backspace": "\u{8}", "Delete": "\u{7f}",
                "Home": UIKeyCommand.inputHome, "PageUp": UIKeyCommand.inputPageUp,
                "PageDown": UIKeyCommand.inputPageDown][code]
    }
    static func commands(action: Selector) -> [UIKeyCommand] {
        mapping.keys.compactMap { input(for: $0) }.flatMap { input in
            [UIKeyModifierFlags(), .shift].map { modifiers in
                let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }
    }
    static func binding(for command: UIKeyCommand) -> Binding? {
        guard let code = mapping.keys.first(where: { input(for: $0) == command.input }) else { return nil }
        return binding(for: code)
    }
    static func isEditing(in view: UIView?) -> Bool {
        guard let view else { return false }
        if view.isFirstResponder && view is UITextInput { return true }
        return view.subviews.contains { isEditing(in: $0) }
    }
}
