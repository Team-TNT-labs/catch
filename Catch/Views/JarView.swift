import SwiftUI
import SpriteKit

/// 읽기 전용 물리 항아리(타 유저 수집 표시용).
@MainActor
final class ReadonlyJarHolder: ObservableObject {
    let scene: StickerScene
    @Published var isLoading = true
    @Published var isEmpty = false
    private let repo = CatchRepository.shared

    init() {
        scene = StickerScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
    }

    func load(_ source: () async throws -> [CloudCatch]) async {
        isLoading = true
        let catches = (try? await source()) ?? []
        isEmpty = catches.isEmpty
        isLoading = false
        for c in catches {
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard let display = await repo.displayImage(for: c) else { continue }
            let body = await repo.bodyImage(for: c) ?? display
            scene.addCatch(id: c.id, display: display, body: body)
        }
    }
}

struct JarView: View {
    let load: () async throws -> [CloudCatch]
    @StateObject private var holder = ReadonlyJarHolder()

    var body: some View {
        ZStack {
            SpriteView(scene: holder.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()
            if holder.isLoading {
                ProgressView().tint(.white)
            } else if holder.isEmpty {
                Text("아직 수집이 없어요")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .task { await holder.load(load) }
    }
}
