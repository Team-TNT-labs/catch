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
            // Phase1 egress 절감: 항아리 표시(≤126px)엔 본문 썸네일(256px)이면 충분 — 원본(1024px) 다운로드 생략.
            guard let body = await repo.bodyImage(for: c) else { continue }
            let prepared = await Task.detached(priority: .userInitiated) {
                body.whiteStickerBordered()
            }.value
            scene.addCatch(id: c.id, bordered: prepared.bordered, working: prepared.working, body: body)
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
                CatchLoader()
            } else if holder.isEmpty {
                Text("아직 수집이 없어요 🫧")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink.opacity(0.5))
            }
        }
        .task { await holder.load(load) }
    }
}
