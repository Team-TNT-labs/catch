import UIKit

enum StickerStoreError: Error { case encodingFailed }

/// 스티커 PNG 영구 저장 + 매니페스트(JSON) 관리.
/// Documents/stickers/ 아래에 <uuid>.png(표시용), <uuid>_body.png(바디용), manifest.json 보관.
final class StickerStore {
    static let shared = StickerStore()

    private let fm = FileManager.default
    private let bodyMaxDimension: CGFloat = 256

    private var stickersDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("stickers", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var manifestURL: URL { stickersDir.appendingPathComponent("manifest.json") }

    func url(for filename: String) -> URL { stickersDir.appendingPathComponent(filename) }

    /// 누끼 이미지를 영구 저장한다. 방향 정규화 + 바디용 다운스케일 캐시까지 한 번에.
    @discardableResult
    func save(image: UIImage) throws -> Sticker {
        let id = UUID()
        // 방향 정규화 → 저장 해상도 상한(긴 변 1024) → 투명 여백 트림(타이트한 스티커).
        let normalized = image.orientationNormalized()
            .resized(maxDimension: 1024)
            .trimmingTransparentPixels()
        let filename = "\(id.uuidString).png"
        let bodyFilename = "\(id.uuidString)_body.png"

        guard let pngData = normalized.pngData() else { throw StickerStoreError.encodingFailed }
        try pngData.write(to: url(for: filename))

        let bodyImage = normalized.resized(maxDimension: bodyMaxDimension)
        if let bodyData = bodyImage.pngData() {
            try? bodyData.write(to: url(for: bodyFilename))
        }

        let sticker = Sticker(id: id, filename: filename, bodyFilename: bodyFilename, createdAt: Date())
        var all = loadAll()
        all.append(sticker)
        try saveManifest(all)
        return sticker
    }

    func loadAll() -> [Sticker] {
        guard let data = try? Data(contentsOf: manifestURL),
              let stickers = try? JSONDecoder().decode([Sticker].self, from: data) else {
            return []
        }
        return stickers
    }

    func delete(id: UUID) {
        var all = loadAll()
        if let sticker = all.first(where: { $0.id == id }) {
            try? fm.removeItem(at: url(for: sticker.filename))
            try? fm.removeItem(at: url(for: sticker.bodyFilename))
        }
        all.removeAll { $0.id == id }
        try? saveManifest(all)
    }

    func image(for sticker: Sticker) -> UIImage? {
        UIImage(contentsOfFile: url(for: sticker.filename).path)
    }

    func bodyImage(for sticker: Sticker) -> UIImage? {
        UIImage(contentsOfFile: url(for: sticker.bodyFilename).path) ?? image(for: sticker)
    }

    private func saveManifest(_ stickers: [Sticker]) throws {
        let data = try JSONEncoder().encode(stickers)
        try data.write(to: manifestURL, options: .atomic)
    }
}
