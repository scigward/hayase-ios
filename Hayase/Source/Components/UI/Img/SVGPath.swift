//
//  SVGPath.swift
//  Hayase
//

import UIKit

/// Parses the path data (`d`) of an SVG icon: the commands M L H V C S A Z and their relative
/// forms, which are all the interface's animated icons use.
enum SVGPath {
    static func path(_ data: String) -> CGPath {
        var reader = Reader(Array(data))
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var command: Character = "M"

        while true {
            reader.skipSeparators()
            if reader.isAtEnd { break }
            if let letter = reader.command() { command = letter }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            var cubicControl: CGPoint?

            switch Character(command.uppercased()) {
            case "M":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = CGPoint(x: base.x + x, y: base.y + y)
                subpathStart = current
                path.move(to: current)
                command = relative ? "l" : "L"   // further pairs are line-tos
            case "L":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = CGPoint(x: base.x + x, y: base.y + y)
                path.addLine(to: current)
            case "H":
                guard let x = reader.number() else { return path }
                current = CGPoint(x: base.x + x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = reader.number() else { return path }
                current = CGPoint(x: current.x, y: base.y + y)
                path.addLine(to: current)
            case "C":
                guard let x1 = reader.number(), let y1 = reader.number(),
                      let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number() else { return path }
                let control2 = CGPoint(x: base.x + x2, y: base.y + y2)
                let end = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: end, control1: CGPoint(x: base.x + x1, y: base.y + y1), control2: control2)
                cubicControl = control2
                current = end
            case "S":
                guard let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number() else { return path }
                let control1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let control2 = CGPoint(x: base.x + x2, y: base.y + y2)
                let end = CGPoint(x: base.x + x, y: base.y + y)
                path.addCurve(to: end, control1: control1, control2: control2)
                cubicControl = control2
                current = end
            case "A":
                guard let rx = reader.number(), let ry = reader.number(), let rotation = reader.number(),
                      let large = reader.flag(), let sweep = reader.flag(),
                      let x = reader.number(), let y = reader.number() else { return path }
                let end = CGPoint(x: base.x + x, y: base.y + y)
                addArc(to: path, from: current, radii: CGSize(width: abs(rx), height: abs(ry)),
                       rotation: rotation, large: large, sweep: sweep, end: end)
                current = end
            case "Z":
                path.closeSubpath()
                current = subpathStart
            default:
                return path
            }
            lastCubicControl = cubicControl
        }
        return path
    }

    /// SVG implementation notes F.6.5: the endpoint arc, as at most quarter-turn cubic curves.
    private static func addArc(to path: CGMutablePath, from start: CGPoint, radii: CGSize,
                               rotation: CGFloat, large: Bool, sweep: Bool, end: CGPoint) {
        var rx = radii.width, ry = radii.height
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let scale = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if scale > 1 {
            rx *= scale.squareRoot()
            ry *= scale.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let factor = (large == sweep ? -1 : 1) * max(0, numerator / denominator).squareRoot()
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(segments)
        let handle = 4 / 3 * tan(step / 4)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * x * cosPhi - ry * y * sinPhi, y: cy + rx * x * sinPhi + ry * y * cosPhi)
        }
        for index in 0..<segments {
            let from = theta + CGFloat(index) * step
            let to = from + step
            path.addCurve(to: point(cos(to), sin(to)),
                          control1: point(cos(from) - handle * sin(from), sin(from) + handle * cos(from)),
                          control2: point(cos(to) + handle * sin(to), sin(to) - handle * cos(to)))
        }
    }

    private struct Reader {
        private let characters: [Character]
        private var index = 0

        init(_ characters: [Character]) {
            self.characters = characters
        }

        var isAtEnd: Bool { index >= characters.count }

        mutating func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == "," || characters[index] == "\n" {
                index += 1
            }
        }

        mutating func command() -> Character? {
            guard index < characters.count, characters[index].isLetter else { return nil }
            defer { index += 1 }
            return characters[index]
        }

        /// A number; a second `.` or a sign starts the next one (`.855.506`, `1-.5`).
        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = index
            var seenDot = false
            var seenDigit = false
            if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    seenDigit = true
                } else if character == ".", !seenDot {
                    seenDot = true
                } else {
                    break
                }
                index += 1
            }
            guard seenDigit, let value = Double(String(characters[start..<index])) else { return nil }
            return CGFloat(value)
        }

        /// An arc flag is a single `0` or `1`, and may be run into the next number.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count, characters[index] == "0" || characters[index] == "1" else { return nil }
            defer { index += 1 }
            return characters[index] == "1"
        }
    }
}
