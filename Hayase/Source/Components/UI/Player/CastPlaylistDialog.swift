//
//  CastPlaylistDialog.swift
//  Hayase
//
//  Created by scigward.
//

// Mirrors: hayase-app/interface/src/lib/components/ui/dialog/dialog-overlay.svelte
// and dialog-content.svelte, as instantiated by castplayer.svelte's Playlist
// Dialog.Root/Dialog.Content (lines 131-144) and button/index.ts's `ghost`
// button variant for each row. Scoped to this one call site — Hayase has no
// general-purpose ui/dialog port yet, and building one wasn't what this
// feature needed.

import UIKit

final class CastPlaylistDialog: UIViewController {
    struct Item {
        let title: String
        let action: () -> Void
    }

    private let items: [Item]
    private var itemActions: [() -> Void] = []

    // dialog-overlay.svelte: `custom-bg` + `backdrop-blur-sm`. custom-bg is a
    // repeating 40deg diagonal hatch (`repeating-linear-gradient(40deg, #1114
    // 0, #5554 1px, #5554 5px, #1114 6px, #1114 10px)`) whose own comment
    // says it exists only to hide banding in the CSS backdrop-filter blur —
    // a rendering workaround with no equivalent problem in UIKit's blur.
    // Reproduced anyway via a tiled pattern image rather than approximated
    // as a flat tint, per "match exactly, don't substitute close-enough."
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let hatchView = UIView()
    private let dismissGestureView = UIView()

    // dialog-content.svelte base classes merged with castplayer.svelte's
    // override: bg-background (base bg-popover overridden), border-4
    // (base border overridden), p-10 py-6, max-w-5xl (base max-w-lg
    // overridden), w-auto (base w-full overridden), rounded-xl, gap-4,
    // items-center flex flex-col, max-h-[calc(100%-1rem)], overflow-y-auto.
    private let card = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    // Dialog.Close: `absolute right-4 top-4 rounded-sm`, Cross2 `size-4`.
    private let closeButton = UIButton(type: .system)

    private var cardTransform: CGAffineTransform {
        CGAffineTransform(scaleX: 0.95, y: 0.95).translatedBy(x: 0, y: -8)   // flyAndScale defaults: start 0.95, y -8
    }

    init(items: [Item]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — CastPlaylistDialog is only created programmatically")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupBackdrop()
        setupCard()
        populateItems()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        card.alpha = 0
        card.transform = cardTransform
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {   // duration: 200 (castplayer.svelte override)
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    private func dismiss(animated: Bool) {
        guard animated else {
            dismiss(animated: false, completion: nil)
            return
        }
        UIView.animate(withDuration: 0.15, animations: {   // dialog-overlay.svelte fade: duration 150
            self.card.alpha = 0
            self.card.transform = self.cardTransform
            self.blurView.alpha = 0
            self.hatchView.alpha = 0
        }, completion: { _ in
            self.dismiss(animated: false, completion: nil)
        })
    }

    private func setupBackdrop() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)

        hatchView.translatesAutoresizingMaskIntoConstraints = false
        hatchView.backgroundColor = UIColor(patternImage: Self.hatchPatternImage())
        view.addSubview(hatchView)

        dismissGestureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dismissGestureView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        dismissGestureView.addGestureRecognizer(tap)

        for v in [blurView, hatchView, dismissGestureView] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: view.topAnchor),
                v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }

    @objc private func backdropTapped() {
        dismiss(animated: true)
    }

    /// `repeating-linear-gradient(40deg, #1114 0, #5554 1px, #5554 5px,
    /// #1114 6px, #1114 10px)` — CSS 4-digit hex shorthand: #1114 =
    /// rgba(17,17,17,0.267), #5554 = rgba(85,85,85,0.267). One 10pt-tall
    /// repeat unit, rotated 40deg, tiled as a UIColor pattern image.
    private static func hatchPatternImage() -> UIImage {
        let tileSize: CGFloat = 10
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: tileSize, height: tileSize))
        let dark = UIColor(red: 17.0 / 255, green: 17.0 / 255, blue: 17.0 / 255, alpha: 68.0 / 255)
        let light = UIColor(red: 85.0 / 255, green: 85.0 / 255, blue: 85.0 / 255, alpha: 68.0 / 255)
        let tile = renderer.image { ctx in
            dark.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: tileSize, height: 1))
            light.setFill()
            ctx.fill(CGRect(x: 0, y: 1, width: tileSize, height: 4))
            // 5-6pt band interpolates light->dark; a hard edge here is an
            // invisible-at-runtime simplification of a 1pt antialiasing seam.
            dark.setFill()
            ctx.fill(CGRect(x: 0, y: 5, width: tileSize, height: 5))
        }
        guard let cgImage = tile.cgImage else { return tile }
        let rotated = UIGraphicsImageRenderer(size: CGSize(width: tileSize, height: tileSize))
        return rotated.image { ctx in
            ctx.cgContext.translateBy(x: tileSize / 2, y: tileSize / 2)
            ctx.cgContext.rotate(by: 40 * .pi / 180)
            ctx.cgContext.translateBy(x: -tileSize / 2, y: -tileSize / 2)
            ctx.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        }
    }

    private func setupCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.HayaseTheme.background   // bg-background
        card.layer.borderWidth = 4   // border-4
        card.layer.borderColor = UIColor.HayaseTheme.border.cgColor
        card.layer.cornerRadius = 12   // rounded-xl
        card.clipsToBounds = true
        view.addSubview(card)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false   // *::-webkit-scrollbar { display: none }
        card.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16   // gap-4
        stack.alignment = .center   // items-center — buttons size to content, not stretched
        scrollView.addSubview(stack)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage.hayaseIcon("x", pointSize: 16), for: .normal)   // Cross2 (radix-icons) size-4=16px; lucide "x" is the closest bundled equivalent
        closeButton.tintColor = UIColor.HayaseTheme.foreground
        closeButton.layer.cornerRadius = 2   // rounded-sm
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card.addSubview(closeButton)

        let widthConstraint = card.widthAnchor.constraint(lessThanOrEqualToConstant: 1024)   // max-w-5xl = 64rem

        // The card has no intrinsic height (a UIScrollView's frame doesn't
        // follow its content); hug the content up to the max-h cap, then let
        // the scroll view take over. 64 = 8+8 outer margin + 24+24 (py-6).
        let hugContent = scrollView.heightAnchor.constraint(equalTo: stack.heightAnchor)
        hugContent.priority = .defaultHigh
        let maxHeight = scrollView.heightAnchor.constraint(
            lessThanOrEqualTo: view.heightAnchor, constant: -64)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            widthConstraint,
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8),
            // max-h-[calc(100%-1rem)]: 1rem (16pt) total headroom, split top/bottom.
            card.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 8),
            card.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),

            closeButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),   // top-4
            closeButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),   // right-4
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),   // py-6
            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),   // p-10 (horizontal)
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),
            hugContent,
            maxHeight,
            card.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 24),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func populateItems() {
        for item in items {
            // button/index.ts `ghost` variant: base h-9 px-4 py-2 rounded-md
            // text-sm font-medium; select:bg-secondary-foreground/20 for the
            // pressed state (`.isHighlighted` here — iOS has no hover).
            // Plain UIButton target-actions rather than UIButton.Configuration/
            // UIAction (iOS 15+) to match this codebase's actual minimum
            // target and its existing button style throughout the player.
            let button = GhostListButton(type: .system)
            button.setTitle(item.title, for: .normal)
            button.setTitleColor(UIColor.HayaseTheme.foreground, for: .normal)
            button.titleLabel?.font = .nunito(ofSize: 14, weight: .medium)   // text-sm font-medium
            button.titleLabel?.lineBreakMode = .byTruncatingTail   // text-ellipsis text-nowrap overflow-clip
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)   // py-2 px-4
            button.layer.cornerRadius = 6   // rounded-md
            button.clipsToBounds = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true   // h-9
            button.addTarget(self, action: #selector(playlistItemTapped(_:)), for: .touchUpInside)
            itemActions.append(item.action)
            button.tag = itemActions.count - 1
            stack.addArrangedSubview(button)
        }
    }

    @objc private func playlistItemTapped(_ sender: UIButton) {
        guard itemActions.indices.contains(sender.tag) else { return }
        let action = itemActions[sender.tag]
        dismiss(animated: true)
        action()
    }
}

/// select:bg-secondary-foreground/20 — the only interaction state a plain
/// ghost `Button` has on web, translated to iOS's highlighted/pressed state.
private final class GhostListButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.HayaseTheme.foreground.withAlphaComponent(0.2)
                : .clear
        }
    }
}
