//
//  SplashPage.swift
//  Hayase
//
//  Mirrors: src/routes/+page.svelte and src/routes/+page.ts, the page the app opens on
//
//    <div class='size-full flex justify-center items-center'>
//      <div class='size-10 relative logo-container' on:animationend|self={navigate}>…</div>
//    </div>
//
//    async function navigate () { await promise; goto(data.goto, { replaceState: true }) }
//
//  On a black screen the logo, 40pt across, comes in from five times its size, in two colours that come
//  together, with light streaks over it that fade; when the scale ends the app goes on, replacing this page,
//  to Home, or to the setup if it has not been done (`data.goto`). It is shown when the app is opened, not
//  when the interface restarts on the page it was on.
//  The `await promise` of the page is the interface's stores being read and the page that follows loaded,
//  which there is nothing of here.
//

import UIKit

final class SplashViewController: UIViewController {
    private let logo = SplashLogoView()
    private var started = false
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.HayaseTheme.background      // bg-background
        view.addSubview(logo)
        logo.onScaleEnd = { [weak self] in self?.navigate() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        logo.start()
        // The animation can be held up with the app (a call, the screen locked); the page must not wait for it for ever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.navigate() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // size-full flex justify-center items-center, inside `#root` padded by the safe area at its top
        let top = view.safeAreaInsets.top
        let center = CGPoint(x: view.bounds.midX, y: top + (view.bounds.height - top) / 2)
        logo.bounds = CGRect(x: 0, y: 0, width: SplashLogoView.side, height: SplashLogoView.side)
        logo.center = center
    }

    /// `goto(data.goto, { replaceState: true })`
    private func navigate() {
        guard !finished else { return }
        finished = true
        (UIApplication.shared.delegate as? AppDelegate)?.finishSplash()
    }
}
