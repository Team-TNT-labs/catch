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
                    ProgressView().tint(.white.opacity(0.4))
                }
            }
        }
        .task(id: path) {
            image = await CatchRepository.shared.image(at: path)
        }
    }
}
