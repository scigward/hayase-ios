//
//  HayaseInterfaceScale.swift
//  Hayase
//
//  Native equivalent of interface `native.setZoom`.
//

import UIKit

enum HayaseInterfaceScale {
    static func apply(_ value: Double = Settings.uiScale) {
        let work = {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let window = scene.windows.first(where: { $0.isKeyWindow }),
                  let root = window.rootViewController else { return }
            apply(value, to: root, in: window)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    static func apply(_ value: Double = Settings.uiScale,
                      to controller: UIViewController,
                      in window: UIWindow?) {
        guard let window else { return }
        let scale = CGFloat(min(max(value, 0.3), 2.5))
        let windowSize = window.bounds.size
        guard windowSize.width > 0, windowSize.height > 0 else { return }
        let logicalSize = CGSize(width: windowSize.width / scale, height: windowSize.height / scale)
        let targetBounds = CGRect(origin: .zero, size: logicalSize)

        if controller.view.bounds.size != targetBounds.size {
            controller.view.bounds = targetBounds
        }
        let targetTransform = CGAffineTransform(scaleX: scale, y: scale)
        if controller.view.transform != targetTransform {
            controller.view.transform = targetTransform
        }
        controller.view.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
    }
}
