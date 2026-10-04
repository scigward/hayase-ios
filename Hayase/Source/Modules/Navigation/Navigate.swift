//
//  Navigate.swift
//  Hayase
//
//  Mirrors: src/lib/modules/navigate.ts: `inputType`, and what the arrow keys do (`navigate`): focus moves to
//  the nearest element in the direction of the key, among the elements of the dialog that is open, or else of
//  the page. Enter on the focused element is a click (`click`, `hover` and `keywrap` of navigate.ts, which the
//  interface's own buttons are written with), and that element is drawn with the tint of
//  `[data-input='dpad'] *:focus`.
//
//  The focus of the interface is the DOM's. UIKit's focus engine is the nearest thing to it, but on iOS it
//  only runs for a hardware keyboard, and the arrows of a game controller never reach it, so the app keeps
//  the focus of the interface itself: `activeElement`, which `isActiveElement` reads along with the
//  engine's `isFocused` (what the views that are drawn `select:` while focused look at).
//
//  What an "element" is: a UIView that the interface would have a `button`, `a[href]`, `input`, `select`,
//  `textarea` or `tabindex` for. They are the controls of the app (a plain `UIControl()` is the click
//  catcher behind a dialog, which has no element in the interface), the text views that can be edited, the
//  rows of a table or collection whose delegate selects them, and the views that say so (`onDPadClick`).
//

import UIKit
import UIKit.UIGestureRecognizerSubclass
import ObjectiveC

// MARK: - inputType

/// `InputType`
enum InputType {
    case mouse
    case touch
    case dpad
}

// MARK: - Elements

/// The interface's `click` and `hover` actions make a node an element: `tabIndex = 0`, `role = 'button'`, and a
/// listener that Enter on the focused node calls. A view that is not a control, but is tapped to do something,
/// says so with `onDPadClick`, which is what a tap on it does.
private var onDPadClickKey: UInt8 = 0

private final class DPadClick {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

extension UIView {
    var onDPadClick: (() -> Void)? {
        get { (objc_getAssociatedObject(self, &onDPadClickKey) as? DPadClick)?.action }
        set { objc_setAssociatedObject(self, &onDPadClickKey, newValue.map(DPadClick.init), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

/// A view that is drawn differently while it is the active element: the `select:` variants of the interface
/// are `focus-visible` as well as hover and active.
protocol ActiveElementObserver: UIView {
    func activeElementDidChange()
}

extension UIView {
    /// `document.activeElement === element`, or the focus of UIKit's engine (a hardware keyboard's)
    var isActiveElement: Bool {
        isFocused || Navigate.activeElement === self
    }
}

// MARK: - Navigate

enum Navigate {
    /// `'up' | 'right' | 'down' | 'left'`
    enum Direction {
        case up
        case right
        case down
        case left
    }

    /// `inputType` changed
    static let inputTypeDidChange = Notification.Name("Navigate.inputTypeDidChange")
    /// The `navigate` event of `focusElement`, which bubbles: the player shows its controls for it. The
    /// object is the element that was focused.
    static let didNavigate = Notification.Name("Navigate.didNavigate")

    /// `inputType`: a touch or the pointer leaves D-pad focus, which a click on the page does in the browser
    /// (the focus goes back to the body).
    static var inputType: InputType = .touch {
        didSet {
            guard inputType != oldValue else { return }
            if inputType != .dpad { blur() }
            NotificationCenter.default.post(name: inputTypeDidChange, object: nil)
        }
    }

    /// `document.activeElement`, when it is not the body
    private(set) static weak var activeElement: UIView?

    private static var window: UIWindow? {
        (UIApplication.shared.delegate as? AppDelegate)?.window
    }

    // MARK: - pointerdown and pointermove

    /// `addEventListener('pointerdown', pointerEvent)` and `'pointermove'`: a touch is `touch`, the pointer of an
    /// iPad is `mouse`. They are set on the window, and see what is done anywhere in it.
    static func observePointer(in window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0 is PointerDownObserver }) else { return }
        window.addGestureRecognizer(PointerDownObserver(target: nil, action: nil))
        let hover = UIHoverGestureRecognizer(target: PointerMoveObserver.shared, action: #selector(PointerMoveObserver.moved(_:)))
        window.addGestureRecognizer(hover)
    }

    /// `pointerdown`: sees each touch as it lands and fails at once, so no other recognizer is held up or cancelled
    private final class PointerDownObserver: UIGestureRecognizer {
        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first {
                Navigate.inputType = touch.type == .indirectPointer ? .mouse : .touch
            }
            state = .failed
        }
    }

    /// `pointermove`
    private final class PointerMoveObserver: NSObject {
        static let shared = PointerMoveObserver()

        @objc func moved(_ recognizer: UIHoverGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else { return }
            Navigate.inputType = .mouse
        }
    }

    // MARK: - navigate

    private static var repeatCount = 0

    /// `navigate(e)`: an arrow key was pressed. `isRepeat` is `e.repeat`.
    static func navigate(_ direction: Direction, isRepeat: Bool = false) {
        // slow down, so its not as jarring
        repeatCount = isRepeat ? (repeatCount + 1) % 8 : 0
        guard repeatCount == 0 else { return }
        inputType = .dpad
        navigateDPad(direction)
    }

    /// `navigateDPad`
    private static func navigateDPad(_ direction: Direction) {
        guard let container = container else { return }
        let elements = focusableElements(in: container)

        guard let current = liveActiveElement(in: container) else {
            focusElement(firstElement(of: elements))
            return
        }

        if current.isFirstResponder, let input = current as? UITextInput, let range = input.selectedTextRange {
            // the cursor moves in an input until it is at the end the key goes towards
            if direction == .left, input.offset(from: input.beginningOfDocument, to: range.start) != 0 { return }
            if direction == .right, input.offset(from: range.end, to: input.endOfDocument) != 0 { return }
        }

        guard let window = container.window else { return }
        let others = elements.filter { $0 !== current }
        let rects = others.map { $0.convert($0.bounds, to: window) }
        let currentRect = current.convert(current.bounds, to: window)
        guard let index = Geometry.nearest(to: currentRect, in: rects, direction: direction, viewport: window.bounds.size) else { return }
        focusElement(others[index])
    }

    /// The elements are put in the order of reading, as the DOM is, where the view order of UIKit is the order
    /// of what is in front.
    private static func firstElement(of elements: [UIView]) -> UIView? {
        guard let window = container?.window else { return elements.first }
        return elements.min { lhs, rhs in
            let left = lhs.convert(lhs.bounds, to: window)
            let right = rhs.convert(rhs.bounds, to: window)
            return left.minY != right.minY ? left.minY < right.minY : left.minX < right.minX
        }
    }

    // MARK: - Where

    /// `document.querySelector('[role="dialog"]') ?? ... ?? document.body`: the controller that is on top is
    /// what the arrow keys move in, as a dialog keeps the focus inside it.
    static var container: UIView? {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top?.viewIfLoaded
    }

    /// The active element when it is still on the page that is shown; else the body
    static func liveActiveElement(in container: UIView) -> UIView? {
        guard let element = activeElement, element.isDescendant(of: container) else { return nil }
        return element
    }

    // MARK: - Focus

    /// `focusElement`
    @discardableResult
    static func focusElement(_ element: UIView?) -> Bool {
        guard let element else { return false }
        let previous = activeElement
        activeElement = element
        // `element.focus()` takes the focus from an input, which puts its keyboard away
        element.window?.endEditing(true)
        showFocusFill(on: element)
        scrollIntoView(element)
        if previous !== element { (previous as? ActiveElementObserver)?.activeElementDidChange() }
        (element as? ActiveElementObserver)?.activeElementDidChange()
        NotificationCenter.default.post(name: didNavigate, object: element)
        return true
    }

    private static func blur() {
        guard let previous = activeElement else { return }
        activeElement = nil
        focusFill.removeFromSuperview()
        (previous as? ActiveElementObserver)?.activeElementDidChange()
    }

    // MARK: - `*:focus`

    /// `[data-input='dpad'] *:focus { border-image: fill 0 linear-gradient(--ring at 30%) }`: a tint over the
    /// element, above its background and under what is in it. Like a border image it is not rounded.
    private final class FocusFill: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            autoresizingMask = [.flexibleWidth, .flexibleHeight]
            backgroundColor = UIColor.HayaseTheme.ring.withAlphaComponent(0.3)
        }

        required init?(coder: NSCoder) {
            nil
        }
    }

    private static let focusFill = FocusFill()

    private static func showFocusFill(on element: UIView) {
        let host = (element as? UICollectionViewCell)?.contentView
            ?? (element as? UITableViewCell)?.contentView
            ?? element
        focusFill.removeFromSuperview()
        focusFill.frame = host.bounds
        host.insertSubview(focusFill, at: 0)
    }

    // MARK: - scrollIntoView

    /// `element.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' })`: every scroll view
    /// the element is in is moved to have it in the middle, as far as it can go.
    private static func scrollIntoView(_ element: UIView) {
        var ancestor = element.superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { center(element, in: scrollView) }
            ancestor = view.superview
        }
    }

    private static func center(_ element: UIView, in scrollView: UIScrollView) {
        let rect = scrollView.convert(element.bounds, from: element)
        let inset = scrollView.adjustedContentInset
        var offset = scrollView.contentOffset

        let minX = -inset.left
        let maxX = scrollView.contentSize.width - scrollView.bounds.width + inset.right
        if maxX > minX { offset.x = min(max(rect.midX - scrollView.bounds.width / 2, minX), maxX) }

        let minY = -inset.top
        let maxY = scrollView.contentSize.height - scrollView.bounds.height + inset.bottom
        if maxY > minY { offset.y = min(max(rect.midY - scrollView.bounds.height / 2, minY), maxY) }

        guard offset != scrollView.contentOffset else { return }
        scrollView.setContentOffset(offset, animated: true)
    }

    // MARK: - getKeyboardFocusableElements

    /// The elements in a view, in the order they are found. What is hidden is not there: `checkVisibility()`
    /// is false for it. What has no alpha or does not take touches is, as `opacity-0` and `pointer-events-none`
    /// leave an element in the page: the player's controls are there while it hides them, and the first key
    /// that focuses one brings them back.
    static func focusableElements(in root: UIView) -> [UIView] {
        var elements: [UIView] = []
        func visit(_ view: UIView) {
            for subview in view.subviews {
                guard !subview.isHidden else { continue }
                // `!el.getAttribute('aria-hidden')`
                if !subview.accessibilityElementsHidden, isElement(subview) { elements.append(subview) }
                visit(subview)
            }
        }
        visit(root)
        return elements
    }

    private static func isElement(_ view: UIView) -> Bool {
        if view.onDPadClick != nil { return true }
        if let control = view as? UIControl {
            // a bare UIControl is the click catcher of a dialog or popover: not an element
            return control.isEnabled && type(of: control) != UIControl.self
        }
        if let text = view as? UITextView { return text.isEditable }
        if view is UICollectionViewCell || view is UITableViewCell { return isSelectable(view) }
        return false
    }

    /// A row that its table or collection selects
    private static func isSelectable(_ cell: UIView) -> Bool {
        if let cell = cell as? UICollectionViewCell,
           let collection = cell.enclosing(UICollectionView.self),
           let delegate = collection.delegate,
           delegate.responds(to: #selector(UICollectionViewDelegate.collectionView(_:didSelectItemAt:))),
           let path = collection.indexPath(for: cell) {
            return delegate.collectionView?(collection, shouldSelectItemAt: path) ?? true
        }
        if let cell = cell as? UITableViewCell,
           let table = cell.enclosing(UITableView.self),
           let delegate = table.delegate,
           delegate.responds(to: #selector(UITableViewDelegate.tableView(_:didSelectRowAt:))),
           let path = table.indexPath(for: cell) {
            return delegate.tableView?(table, shouldHighlightRowAt: path) ?? true
        }
        return false
    }

    // MARK: - click

    /// `target.click()`: what a tap on the element does
    static func click(_ element: UIView) {
        if let click = element.onDPadClick {
            click()
            return
        }
        switch element {
        case let field as UITextField:
            field.becomeFirstResponder()
        case let text as UITextView:
            text.becomeFirstResponder()
        case let toggle as UISwitch:
            toggle.setOn(!toggle.isOn, animated: true)
            toggle.sendActions(for: .valueChanged)
        case let control as UIControl:
            control.sendActions(for: .touchUpInside)
        case let cell as UICollectionViewCell:
            if let collection = cell.enclosing(UICollectionView.self), let path = collection.indexPath(for: cell) {
                collection.delegate?.collectionView?(collection, didSelectItemAt: path)
            }
        case let cell as UITableViewCell:
            if let table = cell.enclosing(UITableView.self), let path = table.indexPath(for: cell) {
                table.delegate?.tableView?(table, didSelectRowAt: path)
            }
        default:
            break
        }
    }
}

private extension UIView {
    func enclosing<T: UIView>(_ type: T.Type) -> T? {
        var view = superview
        while let current = view {
            if let match = current as? T { return match }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Geometry

/// What `navigateDPad` does with where the elements are, which is all of it that is not UIKit
private enum Geometry {
    /// `isInViewport`
    static func isInViewport(_ rect: CGRect, viewport: CGSize) -> Bool {
        rect.minY + rect.height >= 0 && rect.minX + rect.width >= 0
            && rect.maxY - rect.height <= viewport.height && rect.maxX - rect.width <= viewport.width
    }

    /// `getElementsInDesiredDirection`: the indices of the candidates that are past the current one
    static func inDirection(of current: CGRect, in candidates: [CGRect], direction: Navigate.Direction, viewport: CGSize) -> [Int] {
        candidates.indices.filter { index in
            let candidate = candidates[index]
            if !isInViewport(candidate, viewport: viewport) && direction == .right { return false }
            switch direction {
            case .right: return candidate.maxX > current.maxX
            case .left: return candidate.minX < current.minX
            case .down: return candidate.maxY > current.maxY
            case .up: return candidate.minY < current.minY
            }
        }
    }

    /// The candidate `navigateDPad` focuses: of those that overlap the current one across the direction, the
    /// closest; else the one whose centre is the closest. Nil when there is none past it.
    static func nearest(to current: CGRect, in candidates: [CGRect], direction: Navigate.Direction, viewport: CGSize) -> Int? {
        let indices = inDirection(of: current, in: candidates, direction: direction, viewport: viewport)
        guard !indices.isEmpty else { return nil }
        let isHorizontal = direction == .left || direction == .right

        let scored = indices.map { index -> (index: Int, distance: CGFloat, overlaps: Bool, fallback: CGFloat) in
            let candidate = candidates[index]
            let overlap: CGFloat
            let distance: CGFloat
            if isHorizontal {
                overlap = max(0, min(current.maxY, candidate.maxY) - max(current.minY, candidate.minY))
                distance = direction == .right ? candidate.minX - current.maxX : current.minX - candidate.maxX
            } else {
                overlap = max(0, min(current.maxX, candidate.maxX) - max(current.minX, candidate.minX))
                distance = direction == .down ? candidate.minY - current.maxY : current.minY - candidate.maxY
            }
            // `getDistance`
            let fallback = hypot(candidate.midX - current.midX, candidate.midY - current.midY)
            return (index, distance, overlap > 0, fallback)
        }

        let overlapping = scored.filter { $0.overlaps }
        if !overlapping.isEmpty {
            return overlapping.min { $0.distance < $1.distance }?.index
        }
        return scored.min { $0.fallback < $1.fallback }?.index
    }
}
