// Mirrors options.svelte's Keybinds view and player/maps.ts keyboard geometry.
import UIKit

final class PlayerKeybindsView: UIView, UIDragInteractionDelegate, UIDropInteractionDelegate {
    var onAction: ((String, Bool) -> Void)?
    private struct Key {
        let code: String
        let width: CGFloat
        let dark: Bool
        init(_ code: String, _ width: CGFloat = 4, dark: Bool = false) {
            self.code = code; self.width = width; self.dark = dark
        }
    }
    private static let keys: [Key] = [
        Key("Escape", dark: true), Key("Digit1"), Key("Digit2"), Key("Digit3"), Key("Digit4"), Key("Digit5"),
        Key("Digit6"), Key("Digit7"), Key("Digit8"), Key("Digit9"), Key("Digit0"), Key("Minus"), Key("Equal"),
        Key("Backspace", 9, dark: true), Key("Delete", dark: true),
        Key("Tab", 6.5, dark: true), Key("KeyQ"), Key("KeyW"), Key("KeyE"), Key("KeyR"), Key("KeyT"),
        Key("KeyY"), Key("KeyU"), Key("KeyI"), Key("KeyO"), Key("KeyP"), Key("BracketLeft"), Key("BracketRight"),
        Key("Backslash", 6.5, dark: true), Key("Home", dark: true),
        Key("CapsLock", 8, dark: true), Key("KeyA"), Key("KeyS"), Key("KeyD"), Key("KeyF"), Key("KeyG"),
        Key("KeyH"), Key("KeyJ"), Key("KeyK"), Key("KeyL"), Key("Semicolon"), Key("Quote"),
        Key("Enter", 10, dark: true), Key("PageUp", dark: true),
        Key("ShiftLeft", 10.5, dark: true), Key("KeyZ"), Key("KeyX"), Key("KeyC"), Key("KeyV"), Key("KeyB"),
        Key("KeyN"), Key("KeyM"), Key("Comma"), Key("Period"), Key("Slash"), Key("ShiftRight", 7.5, dark: true),
        Key("ArrowUp", dark: true), Key("PageDown", dark: true),
        Key("ControlLeft", 6.5, dark: true), Key("MetaLeft", dark: true), Key("AltLeft", 6.5, dark: true),
        Key("Space", 29, dark: true), Key("AltRight", 6.5, dark: true), Key("ContextMenu", 6.5, dark: true),
        Key("ArrowLeft", dark: true), Key("ArrowDown", dark: true), Key("ArrowRight", dark: true),
    ]
    private let descriptionLabel = UILabel()
    private let descriptionCard = UIView()
    private let keyboard = UIView()
    private var buttons: [UIButton] = []
    private var hoveredCode: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        descriptionCard.backgroundColor = UIColor.HayaseTheme.background
        descriptionCard.layer.cornerRadius = 6
        descriptionLabel.textColor = UIColor.HayaseTheme.foreground
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionCard.addSubview(descriptionLabel)
        addSubview(descriptionCard)
        keyboard.backgroundColor = .black // app.css overrides .svelte-keybinds background
        addSubview(keyboard)
        for key in Self.keys {
            let button = UIButton(type: .custom)
            button.accessibilityIdentifier = key.code
            button.accessibilityLabel = Self.label(for: key.code)
            button.backgroundColor = UIColor(red: key.dark ? 25/255 : 37/255,
                                             green: key.dark ? 28/255 : 40/255,
                                             blue: key.dark ? 32/255 : 44/255, alpha: 1)
            button.tintColor = UIColor(white: 238/255, alpha: 1)
            button.setTitleColor(button.tintColor, for: .normal)
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            button.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
            let drag = UIDragInteraction(delegate: self)
            drag.isEnabled = true
            button.addInteraction(drag)
            button.addInteraction(UIDropInteraction(delegate: self))
            keyboard.addSubview(button)
            buttons.append(button)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func containsContent(at point: CGPoint) -> Bool {
        keyboard.frame.contains(point) || descriptionCard.frame.contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Tailwind lg is viewport width, not size class or pointer type.
        let large = (window?.bounds.width ?? bounds.width) >= 1024
        let em: CGFloat = large ? 12 : 6
        let keyboardSize = CGSize(width: 82 * em, height: 27 * em)
        descriptionLabel.font = .nunito(ofSize: large ? 18 : 14, weight: .bold)
        let textSize = descriptionLabel.sizeThatFits(CGSize(width: max(1, bounds.width - 32), height: CGFloat.greatestFiniteMagnitude))
        let cardSize = CGSize(width: min(bounds.width, textSize.width + 32), height: textSize.height + 24)
        let top = max(0, (bounds.height - cardSize.height - 16 - keyboardSize.height) / 2)
        descriptionCard.frame = CGRect(x: (bounds.width - cardSize.width) / 2, y: top, width: cardSize.width, height: cardSize.height)
        descriptionLabel.frame = descriptionCard.bounds.insetBy(dx: 16, dy: 12)
        keyboard.frame = CGRect(x: (bounds.width - keyboardSize.width) / 2,
                                y: descriptionCard.frame.maxY + 16, width: keyboardSize.width, height: keyboardSize.height)
        keyboard.layer.cornerRadius = 0.4 * em
        var x = em, y = em
        for (key, button) in zip(Self.keys, buttons) {
            let outerWidth = (key.width + 1) * em
            if x + outerWidth > 81 * em + 0.01 { x = em; y += 5 * em }
            button.bounds = CGRect(x: 0, y: 0, width: key.width * em, height: 4 * em)
            button.center = CGPoint(x: x + outerWidth / 2, y: y + 2.5 * em)
            button.layer.cornerRadius = 0.4 * em
            button.titleLabel?.font = .nunito(ofSize: large ? 18 : 6, weight: .regular)
            let inset: CGFloat = large ? 12 : 6
            button.imageEdgeInsets = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
            if let binding = PlayerKeyBindings.binding(for: key.code), let icon = binding.icon {
                let size: CGFloat = large ? 24 : 12
                button.setImage(icon == "play" ? UIImage.hayaseFilledIcon(icon, pointSize: size)
                    : UIImage.hayaseIcon(icon, pointSize: size), for: .normal)
            }
            x += outerWidth
        }
    }

    func refresh() {
        for (key, button) in zip(Self.keys, buttons) {
            let binding = PlayerKeyBindings.binding(for: key.code)
            button.setImage(nil, for: .normal)
            button.setTitle(binding?.icon == nil ? binding?.id : nil, for: .normal)
            button.accessibilityLabel = Self.label(for: key.code) + (binding.map { ": " + $0.description } ?? "")
        }
        updateDescription()
        setNeedsLayout()
    }
    private static func label(for code: String) -> String {
        if code.hasPrefix("Key") { return String(code.dropFirst(3)).lowercased() }
        if code.hasPrefix("Digit") { return String(code.dropFirst(5)) }
        if code.hasPrefix("Arrow") { return String(code.dropFirst(5)) }
        return ["BracketLeft": "[", "BracketRight": "]", "Backslash": "\\", "Semicolon": ";", "Quote": "'",
                "Comma": ",", "Period": ".", "Slash": "/", "Minus": "-", "Equal": "="][code] ?? code
    }
    private func updateDescription() {
        if let code = hoveredCode, let binding = PlayerKeyBindings.binding(for: code) {
            descriptionLabel.text = (Self.label(for: code) + " : " + binding.description).capitalized
        } else { descriptionLabel.text = "Drag And Drop Binds To Change Them" }
        setNeedsLayout()
    }
    @objc private func keyTapped(_ button: UIButton) {
        guard let code = button.accessibilityIdentifier, let binding = PlayerKeyBindings.binding(for: code) else { return }
        onAction?(binding.id, false)
    }
    @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
        guard let button = recognizer.view as? UIButton else { return }
        let active = recognizer.state == .began || recognizer.state == .changed
        hoveredCode = active ? button.accessibilityIdentifier : nil
        UIView.animate(withDuration: 0.2) { button.transform = active ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity }
        updateDescription()
    }
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let code = interaction.view?.accessibilityIdentifier, PlayerKeyBindings.binding(for: code) != nil else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider(object: code as NSString))
        item.localObject = code
        return [item]
    }
    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) { interaction.view?.alpha = 0.2 }
    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
        interaction.view?.alpha = 1
    }
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil && session.items.first?.localObject is String
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .move)
    }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) { interaction.view?.alpha = 0.2 }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) { interaction.view?.alpha = 1 }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) { interaction.view?.alpha = 1 }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard let source = session.items.first?.localObject as? String,
              PlayerKeyBindings.binding(for: source) != nil,
              let destination = interaction.view?.accessibilityIdentifier else { return }
        PlayerKeyBindings.move(from: source, to: destination)
        interaction.view?.alpha = 1
        refresh()
    }
}
