import SwiftUI
import SpriteKit

/// 씬을 뷰 갱신과 무관하게 한 번만 생성해 보관한다.
final class SceneHolder: ObservableObject {
    let scene: StickerScene

    init() {
        let scene = StickerScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        self.scene = scene
    }
}

/// 홈 = 스티커 더미(물리). 좌측 상단 버튼으로 카메라 뷰를 연다.
struct HomeView: View {
    @StateObject private var holder = SceneHolder()
    @State private var showCamera = false
    @State private var isEmpty = StickerStore.shared.loadAll().isEmpty

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SpriteView(scene: holder.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            if isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.fingers.spread")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("무언가를 찍어 스티커로 모아보세요")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            // 좌측 상단 카메라 버튼
            Button {
                showCamera = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 8)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 40)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraFlowView(
                onCatch: { sticker in
                    holder.scene.addSticker(sticker)
                    isEmpty = false
                },
                onClose: { showCamera = false }
            )
        }
    }
}

#Preview {
    HomeView()
}
