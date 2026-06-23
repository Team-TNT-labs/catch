import SwiftUI
import UIKit

/// 항아리 배경 설정(Pro) — 기본 그라데이션 / 단색 / 사진. 로컬 영속.
/// (전부 메인스레드에서 접근 — SwiftUI UI + SKScene 메인루프)
final class JarBackgroundStore: ObservableObject {
    static let shared = JarBackgroundStore()

    /// 선택 가능한 단색 팔레트(hex). nil 선택 = 기본 그라데이션.
    static let palette: [UInt] = [
        0x0E0E0C, 0x1B2A1A, 0x14233A, 0x2A1B33, 0x3A1B22,
        0x0B3D2E, 0x6B5BD6, 0xD96B6B, 0xE8D26A, 0xF4FFA4
    ]

    @Published private(set) var colorHex: String?
    @Published private(set) var hasPhoto: Bool

    private let fm = FileManager.default
    private let colorKey = "jarBgColorHex"

    private var photoURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("jar_bg.jpg")
    }

    init() {
        colorHex = UserDefaults.standard.string(forKey: colorKey)
        hasPhoto = fm.fileExists(atPath: fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jar_bg.jpg").path)
    }

    var photo: UIImage? {
        guard hasPhoto, let d = try? Data(contentsOf: photoURL) else { return nil }
        return UIImage(data: d)
    }

    var uiColor: UIColor? {
        guard let hex = colorHex, let v = UInt(hex, radix: 16) else { return nil }
        return UIColor(hex: v)
    }

    func setColor(_ hex: UInt) {
        clearPhoto()
        let s = String(format: "%06X", Int(hex))
        colorHex = s
        UserDefaults.standard.set(s, forKey: colorKey)
    }

    func setPhoto(_ image: UIImage) {
        if let d = image.jpegData(compressionQuality: 0.9) { try? d.write(to: photoURL, options: .atomic) }
        hasPhoto = fm.fileExists(atPath: photoURL.path)
        colorHex = nil
        UserDefaults.standard.removeObject(forKey: colorKey)
    }

    func reset() {
        clearPhoto()
        colorHex = nil
        UserDefaults.standard.removeObject(forKey: colorKey)
    }

    private func clearPhoto() {
        try? fm.removeItem(at: photoURL)
        hasPhoto = false
    }
}
