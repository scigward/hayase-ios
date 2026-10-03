//
//  SetupLayout.swift
//  Hayase
//
//  Mirrors: src/routes/setup/+layout.svelte (and src/routes/setup/+layout.ts, which the app's launch stands in for)
//
//    <div class='size-full flex items-center justify-center md:py-20 md:px-4 lg:px-10'>
//      <div class='absolute opacity-25 w-full h-[130%] bg-cover bg-no-repeat bg-[url(/bg_grid.jpg)]
//                  animate-[bg-grid-animate_60s_linear_infinite_alternate]' />
//      <div class='w-full md:max-w-[1140px] h-full md:max-h-[720px] flex-col flex items-center justify-center overflow-clip z-[1]'>
//        <slot />
//      </div>
//    </div>
//
//  It is the root of the app until the setup is finished, in the place of the sidebar shell. The pages
//  change with the crossfade the interface's view transitions give a navigation (see HayaseRouteTransition).
//

import UIKit

/// What a page of the setup is: it knows the width of the window, which `md` and `lg` are asked
/// of, and it can ask the setup to move on.
class SetupPageView: UIView {
    var viewportWidth: CGFloat = 0 {
        didSet { if viewportWidth != oldValue { viewportWidthChanged() } }
    }
    /// A link of the page (`href`) or a button that navigates.
    var navigate: ((SetupRoute) -> Void)?
    /// `goto('/#/app/home', { replaceState: true })` after the last step
    var finish: (() -> Void)?
    /// Where a popover of the page is presented from.
    weak var presenter: UIViewController?

    func viewportWidthChanged() {
        setNeedsLayout()
    }
}

/// `absolute opacity-25 w-full h-[130%] bg-cover bg-no-repeat bg-[url(/bg_grid.jpg)]` with
/// `bg-grid-animate`: the background position runs from `0 100%` to `100% 0` and back, a minute
/// each way, linear. A cover-sized image only has room to move along one axis, so that is the one it does.
final class SetupGridBackground: UIView {
    private static let animationKey = "bg-grid-animate"
    private static let duration: CFTimeInterval = 60

    private let imageView = UIImageView(image: UIImage(named: "SetupGrid"))
    private let startedAt = CACurrentMediaTime()
    private var animatedSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        alpha = 0.25                  // opacity-25
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        guard animatedSize != bounds.size else { return }
        animatedSize = bounds.size

        // bg-cover
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        // background-position: 0 100%  →  100% 0, as the share of the room the image has in the box
        let from = CGPoint(x: 0, y: bounds.height - size.height)
        let to = CGPoint(x: bounds.width - size.width, y: 0)

        imageView.layer.removeAnimation(forKey: Self.animationKey)
        imageView.frame = CGRect(origin: from, size: size)
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(cgPoint: CGPoint(x: from.x + size.width / 2, y: from.y + size.height / 2))
        animation.toValue = NSValue(cgPoint: CGPoint(x: to.x + size.width / 2, y: to.y + size.height / 2))
        animation.duration = Self.duration
        animation.autoreverses = true                     // alternate
        animation.repeatCount = .infinity                 // infinite
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        // A new size goes on from where the animation was, not from the start
        animation.beginTime = imageView.layer.convertTime(startedAt, from: nil)
        animation.fillMode = .both
        imageView.layer.add(animation, forKey: Self.animationKey)
    }
}

final class SetupLayoutView: UIView {
    /// `md:max-w-[1140px]` and `md:max-h-[720px]`
    private static let containerMaxSize = CGSize(width: 1140, height: 720)

    private let grid = SetupGridBackground()
    private let container = UIView()
    private(set) var page: SetupPageView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.HayaseTheme.background      // bg-background
        clipsToBounds = true                                  // overflow-clip of #root
        addSubview(grid)
        container.clipsToBounds = true                        // overflow-clip
        addSubview(container)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// `<slot />`
    func setPage(_ newPage: SetupPageView) {
        page?.removeFromSuperview()
        page = newPage
        container.addSubview(newPage)
        setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }

        // `#root` pads its top with the safe area; `size-full` is the rest
        let top = safeAreaInsets.top
        let outerHeight = max(0, height - top)
        let medium = width >= 768
        let large = width >= 1024
        // md:py-20 md:px-4 lg:px-10
        let paddingY: CGFloat = medium ? 80 : 0
        let paddingX: CGFloat = large ? 40 : (medium ? 16 : 0)
        let availableWidth = max(0, width - 2 * paddingX)
        let availableHeight = max(0, outerHeight - 2 * paddingY)
        let containerWidth = medium ? min(availableWidth, Self.containerMaxSize.width) : availableWidth
        let containerHeight = medium ? min(availableHeight, Self.containerMaxSize.height) : availableHeight
        // items-center justify-center
        container.frame = CGRect(x: (width - containerWidth) / 2, y: top + (outerHeight - containerHeight) / 2,
                                 width: containerWidth, height: containerHeight)

        // The grid is `absolute`, so it stays where it would sit as the only child of the centred
        // flex box, and it is 130% as high as the root, which clips what is outside of it.
        let gridHeight = height * 1.3
        grid.frame = CGRect(x: 0, y: top + outerHeight / 2 - gridHeight / 2, width: width, height: gridHeight)

        page?.frame = container.bounds
        page?.viewportWidth = width
    }
}

final class SetupViewController: UIViewController {
    private let layoutView = SetupLayoutView()
    private let transition = HayaseRouteTransition()
    private(set) var route: SetupRoute

    init(route: SetupRoute = .welcome) {
        self.route = route
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = layoutView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        layoutView.setPage(makePage(for: route))
    }

    /// `goto('/#/setup/…', { replaceState: true })`: the page changes, with the crossfade of the
    /// view transition, and there is no history to go back through.
    func show(_ newRoute: SetupRoute) {
        guard newRoute != route else { return }
        route = newRoute
        view.endEditing(true)
        transition.perform(in: layoutView) { [self] in
            layoutView.setPage(makePage(for: newRoute))
            layoutView.layoutIfNeeded()
        }
    }

    private func makePage(for route: SetupRoute) -> SetupPageView {
        let page: SetupPageView
        switch route {
        case .welcome: page = SetupWelcomePage()
        case .storage: page = SetupStoragePage()
        case .network: page = SetupNetworkPage()
        case .extensions: page = SetupExtensionsPage(parent: self)
        }
        page.navigate = { [weak self] destination in self?.show(destination) }
        page.finish = { [weak self] in self?.finishSetup() }
        page.presenter = self
        return page
    }

    /// Next on the last step: the setup is done (`setup-finished`) and the app starts, on Home.
    private func finishSetup() {
        (UIApplication.shared.delegate as? AppDelegate)?.finishSetup()
    }
}
