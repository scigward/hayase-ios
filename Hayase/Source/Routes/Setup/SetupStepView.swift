//
//  SetupStepView.swift
//  Hayase
//
//  Mirrors: the page shape the three steps of the setup share (storage, network and extensions
//  all render `<Progress step={n} />`, a scrolling body, and `<Footer step={n} {checks} />`)
//
//    container:  flex-col items-center, overflow-clip
//    Progress:   px-6 mt-14 w-full lg:max-w-4xl pb-5
//    body:       space-y-3 lg:max-w-4xl h-full overflow-y-auto, with `pt-5` or `py-8`
//    Footer:     the checks box (mt-auto, lg:max-w-4xl) and the bar (w-full)
//
//  The body is `h-full`, so it takes what the progress and the footer leave, and scrolls.
//

import UIKit

class SetupStepView: SetupPageView {
    /// `lg:max-w-4xl`
    private static let columnMaxWidth: CGFloat = 896

    let step: Int
    private let progress: SetupProgressView
    let footer = SetupFooterView()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let topPadding: CGFloat
    private let bottomPadding: CGFloat
    private var keyboardObserver: NSObjectProtocol?

    /// `pt-5` (the body of storage and network) or `py-8` (the body of the extensions)
    init(step: Int, topPadding: CGFloat, bottomPadding: CGFloat) {
        self.step = step
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        progress = SetupProgressView(step: step)
        super.init(frame: .zero)

        scroll.showsVerticalScrollIndicator = false      // *::-webkit-scrollbar { display: none }
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.keyboardDismissMode = .interactive
        scroll.delaysContentTouches = false
        stack.axis = .vertical
        stack.spacing = 12                                // space-y-3
        scroll.addSubview(stack)

        addSubview(scroll)
        addSubview(progress)
        addSubview(footer)

        progress.onNavigate = { [weak self] route in self?.navigate?(route) }
        footer.onPrev = { [weak self] in
            // PREV = ['/#/setup', '/#/setup/storage', '/#/setup/network']
            guard let self else { return }
            self.navigate?([SetupRoute.welcome, .storage, .network][self.step])
        }
        footer.onNext = { [weak self] in self?.checkNext() }

        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                self?.keyboardChanged(note)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
    }

    /// `checkNext`: the last step is the end of the setup; the others go to the next one.
    private func checkNext() {
        // NEXT = ['/#/setup/network', '/#/setup/extensions', '/#/app/home']
        if step == 2 {
            SetupFlow.markFinished()
            finish?()
        } else {
            navigate?([SetupRoute.network, .extensions][step])
        }
    }

    /// The cards of the body, one under the other.
    func setContent(_ views: [UIView]) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        views.forEach { stack.addArrangedSubview($0) }
        setNeedsLayout()
    }

    /// The content changed its own height.
    func invalidateContentSize() {
        setNeedsLayout()
    }

    private func keyboardChanged(_ note: Notification) {
        guard window != nil,
              let rect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboard = convert(rect, from: nil)
        let overlap = max(0, scroll.frame.maxY - keyboard.minY)
        scroll.contentInset.bottom = overlap
        scroll.verticalScrollIndicatorInsets.bottom = overlap
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        guard width > 0 else { return }
        let large = viewportWidth >= 1024
        // flex-col items-center, lg:max-w-4xl
        let columnWidth = large ? min(width, Self.columnMaxWidth) : width
        let columnX = (width - columnWidth) / 2

        progress.frame = CGRect(x: columnX, y: SetupProgressView.topMargin,
                                width: columnWidth, height: SetupProgressView.height)

        footer.viewportWidth = viewportWidth
        let footerHeight = footer.height(forWidth: width)
        footer.frame = CGRect(x: 0, y: height - footerHeight, width: width, height: footerHeight)

        let bodyTop = SetupProgressView.topMargin + SetupProgressView.height
        scroll.frame = CGRect(x: 0, y: bodyTop, width: width, height: max(0, height - footerHeight - bodyTop))

        stack.arrangedSubviews.compactMap { $0 as? SettingsResponsiveView }
            .forEach { $0.updateLayout(viewportWidth: viewportWidth) }
        stack.frame = CGRect(x: columnX, y: topPadding, width: columnWidth, height: stack.bounds.height)
        let fitted = stack.arrangedSubviews.isEmpty ? 0 : stack.systemLayoutSizeFitting(
            CGSize(width: columnWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        stack.frame.size.height = ceil(fitted)
        stack.layoutIfNeeded()
        scroll.contentSize = CGSize(width: width, height: topPadding + ceil(fitted) + bottomPadding)
    }
}
