//
//  Globe.swift
//  Hayase
//
//  Created by scigward.
//

import UIKit

final class Globe: UIView {
    private let globeLayer = CAShapeLayer()
    private let latitudeLayer = CAShapeLayer()
    private let longitudeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        alpha = 0.8

        globeLayer.fillColor = UIColor.clear.cgColor
        globeLayer.strokeColor = UIColor(white: 0.23, alpha: 0.7).cgColor
        globeLayer.lineWidth = 1

        latitudeLayer.fillColor = UIColor.clear.cgColor
        latitudeLayer.strokeColor = UIColor(white: 0.23, alpha: 0.35).cgColor
        latitudeLayer.lineWidth = 0.7

        longitudeLayer.fillColor = UIColor.clear.cgColor
        longitudeLayer.strokeColor = UIColor(white: 0.23, alpha: 0.35).cgColor
        longitudeLayer.lineWidth = 0.7

        layer.addSublayer(globeLayer)
        layer.addSublayer(latitudeLayer)
        layer.addSublayer(longitudeLayer)

        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = CGFloat.pi * 2
        animation.duration = 48
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        longitudeLayer.add(animation, forKey: "hayase-globe-rotation")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = min(bounds.width, bounds.height)
        let rect = CGRect(x: bounds.maxX - size * 0.65,
                          y: bounds.maxY - size * 0.55,
                          width: size,
                          height: size)

        globeLayer.frame = bounds
        latitudeLayer.frame = bounds
        longitudeLayer.frame = bounds

        globeLayer.path = UIBezierPath(ovalIn: rect).cgPath

        let latitudePath = UIBezierPath()
        for index in 1...4 {
            let y = rect.minY + rect.height * CGFloat(index) / 5
            let inset = abs(y - rect.midY) / rect.height * rect.width * 0.55
            latitudePath.append(UIBezierPath(ovalIn: CGRect(x: rect.minX + inset,
                                                            y: y - rect.height * 0.035,
                                                            width: rect.width - inset * 2,
                                                            height: rect.height * 0.07)))
        }
        latitudeLayer.path = latitudePath.cgPath

        let longitudePath = UIBezierPath()
        for index in 1...4 {
            let x = rect.minX + rect.width * CGFloat(index) / 5
            let inset = abs(x - rect.midX) / rect.width * rect.height * 0.55
            longitudePath.append(UIBezierPath(ovalIn: CGRect(x: x - rect.width * 0.035,
                                                             y: rect.minY + inset,
                                                             width: rect.width * 0.07,
                                                             height: rect.height - inset * 2)))
        }
        longitudeLayer.path = longitudePath.cgPath
    }
}
