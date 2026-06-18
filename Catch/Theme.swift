import SwiftUI
import UIKit

/// SETLOG 무드 — 다크 + 모노 악센트. 대부분 iOS 기본, 몇 군데만 키치.
enum Theme {
    static let ink     = Color.white
    static let muted   = Color(white: 0.55)
    static let surface = Color(white: 0.13)      // 다크 그레이 pill/카드
    static let cream   = Color.black             // 베이스 배경(이름 호환)
    static let coral   = Color(hex: 0xE3FB85)    // 메인 악센트 = 로고 라임(이름 호환)
    static let grape   = Color(hex: 0xC4B0FF)
    static let mint    = Color(hex: 0xE3FB85)
    static let butter  = Color(hex: 0xF6E58D)
    static let lime    = Color(hex: 0xE3FB85)

    static let bgTop    = Color.black
    static let bgBottom = Color.black

    static var background: LinearGradient {
        LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom)
    }

    // SpriteKit 씬 배경(거의 검정 — 컬러 누끼가 튐)
    static let sceneTop = UIColor(white: 0.06, alpha: 1)
    static let sceneBottom = UIColor(white: 0.02, alpha: 1)
}

extension Font {
    /// 터미널/키치 악센트용 모노스페이스.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// 통통한 알약 버튼(다크).
struct CuteButtonStyle: ButtonStyle {
    var bg: Color = Theme.coral
    var fg: Color = .black
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(bg, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 둥근 아이콘 버튼(다크 그레이 — SETLOG 하단 버튼 톤).
struct CuteIconButtonStyle: ButtonStyle {
    var bg: Color = Theme.surface
    var fg: Color = .white
    var size: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(fg)
            .frame(width: size, height: size)
            .background(bg, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
