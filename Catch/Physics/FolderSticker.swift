import UIKit
import SpriteKit
import SwiftUI

/// 폴더 색 팔레트(인덱스 저장). 0 = 라임(기본).
enum FolderPalette {
    static let hexes: [UInt] = [0xE3FB85, 0xC4B0FF, 0xF6E58D, 0xFF9AA2, 0x9AD0FF, 0xB5EAD7, 0xFFB6E1, 0xFFD8A8]
    static func uiColor(_ i: Int?) -> UIColor { UIColor(hex: hexes[(i ?? 0) % hexes.count]) }
    static func color(_ i: Int?) -> Color { Color(hex: hexes[(i ?? 0) % hexes.count]) }
}

/// 폴더를 항아리 속 물리 객체로 표현하는 모양. 저장값(없으면 id 기반 기본).
enum FolderShape: CaseIterable {
    case circle, square, triangle, star, hexagon, heart

    static func forId(_ id: UUID) -> FolderShape {
        let n = id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return allCases[n % allCases.count]
    }

    /// 저장된 인덱스(유효하면) 또는 id 기반 기본.
    static func resolve(_ raw: Int?, id: UUID) -> FolderShape {
        if let raw, raw >= 0, raw < allCases.count { return allCases[raw] }
        return forId(id)
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// 글자가 모양을 뚫지 않도록 모양 내부의 안전 텍스트 박스(정규화 0~1: x중심폭, y중심).
    /// (widthFactor, centerY) — 모양이 가장 넓은 지점에 텍스트를 둔다.
    private var labelBox: (width: CGFloat, centerY: CGFloat) {
        switch self {
        case .circle:   return (0.78, 0.5)
        case .square:   return (0.82, 0.5)
        case .hexagon:  return (0.74, 0.5)
        case .triangle: return (0.60, 0.66)   // 아래쪽이 넓다
        case .star:     return (0.50, 0.52)   // 가운데 좁다
        case .heart:    return (0.66, 0.42)   // 위쪽 로브 사이가 넓다
        }
    }

    // MARK: - Path

    func path(in r: CGRect) -> UIBezierPath {
        switch self {
        case .circle:  return UIBezierPath(ovalIn: r)
        case .square:  return UIBezierPath(roundedRect: r, cornerRadius: r.width * 0.18)
        case .triangle:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.close(); return p
        case .star:    return Self.star(in: r, points: 5, inner: 0.46)
        case .hexagon: return Self.polygon(in: r, sides: 6, rotation: .pi / 6)
        case .heart:   return Self.heart(in: r)
        }
    }

    private static func polygon(in r: CGRect, sides: Int, rotation: CGFloat = 0) -> UIBezierPath {
        let p = UIBezierPath()
        let c = CGPoint(x: r.midX, y: r.midY)
        let rad = min(r.width, r.height) / 2
        for i in 0..<sides {
            let a = rotation - .pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(sides)
            let pt = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close(); return p
    }

    private static func star(in r: CGRect, points: Int, inner: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        let c = CGPoint(x: r.midX, y: r.midY)
        let outer = min(r.width, r.height) / 2
        let innerR = outer * inner
        for i in 0..<(points * 2) {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let rad = i.isMultiple(of: 2) ? outer : innerR
            let pt = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close(); return p
    }

    private static func heart(in r: CGRect) -> UIBezierPath {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        // 자기교차 없는 단일 닫힌 루프(4 커브).
        let p = UIBezierPath()
        p.move(to: pt(0.5, 0.27))
        p.addCurve(to: pt(0.0, 0.27), controlPoint1: pt(0.42, 0.03), controlPoint2: pt(0.0, 0.03))
        p.addCurve(to: pt(0.5, 1.0),  controlPoint1: pt(0.0, 0.56), controlPoint2: pt(0.5, 0.72))
        p.addCurve(to: pt(1.0, 0.27), controlPoint1: pt(0.5, 0.72), controlPoint2: pt(1.0, 0.56))
        p.addCurve(to: pt(0.5, 0.27), controlPoint1: pt(1.0, 0.03), controlPoint2: pt(0.58, 0.03))
        p.close(); return p
    }

    // MARK: - Render

    /// 색 채움 + 흰 테두리 + 폴더 이름. 스티커와 구분되는 명확한 '폴더' 룩.
    func image(name: String, fill: UIColor, size: CGFloat = 240) -> UIImage {
        let pad = size * 0.1
        let rect = CGRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = false; fmt.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt).image { _ in
            let path = self.path(in: rect)
            fill.setFill(); path.fill()
            UIColor.white.setStroke(); path.lineWidth = size * 0.055; path.stroke()

            // 모양별 안전 박스 — 글자가 모양을 뚫지 않게 폭/위치 제한 + 폰트 축소 + 잘림.
            let box = self.labelBox
            let boxW = rect.width * box.width
            let para = NSMutableParagraphStyle()
            para.alignment = .center; para.lineBreakMode = .byTruncatingTail
            let text = name as NSString

            var fontSize = size * 0.15
            while fontSize > size * 0.085 {
                let w = text.size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: .heavy)]).width
                if w <= boxW { break }
                fontSize -= size * 0.01
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: UIColor.black,
                .paragraphStyle: para
            ]
            let th = fontSize * 1.3
            let tr = CGRect(x: rect.minX + (rect.width - boxW) / 2,
                            y: rect.minY + rect.height * box.centerY - th / 2,
                            width: boxW, height: th)
            text.draw(in: tr, withAttributes: attrs)
        }
    }

    /// 안정적으로 쌓이도록 단순화한 물리 바디(볼록 모양만 폴리곤, 나머지는 원).
    func physicsBody(displaySize s: CGSize) -> SKPhysicsBody {
        switch self {
        case .square:
            return SKPhysicsBody(rectangleOf: CGSize(width: s.width * 0.78, height: s.height * 0.78))
        default:
            return SKPhysicsBody(circleOfRadius: min(s.width, s.height) * 0.42)
        }
    }
}
