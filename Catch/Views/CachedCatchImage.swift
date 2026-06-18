import SwiftUI

/// Storage 캐치 이미지를 캐시 우선으로 로드해 표시한다.
struct CachedCatchImage: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ZStack {
                    Rectangle().fill(.white.opacity(0.05))
                    CatchLoader(size: 6, color: .white.opacity(0.35))
                }
            }
        }
        .task(id: path) {
            image = await CatchRepository.shared.image(at: path)
        }
    }
}

/// 캐치 이미지를 흰 테두리 스티커로 표시(그리드용). 테두리 생성은 백그라운드 + 메모리 캐시.
struct BorderedStickerImage: View {
    let path: String
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                CatchLoader(size: 6, color: .white.opacity(0.35))
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        let key = path as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        guard let raw = await CatchRepository.shared.image(at: path) else { return }
        let bordered = await Task.detached(priority: .userInitiated) { raw.whiteStickerBordered().bordered }.value
        Self.cache.setObject(bordered, forKey: key)
        image = bordered
    }
}
