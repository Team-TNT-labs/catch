import SwiftUI

/// 촬영 → 스캔 누끼 → Catch 저장 흐름. 메인에서 왼쪽 스와이프로 슬라이드 인된다.
/// Catch 성공 시 `onCatch`로 새 Sticker를 전달하고, 닫을 땐 `onClose`를 호출한다.
struct CameraFlowView: View {
    var onCatch: (Sticker) -> Void
    var onClose: () -> Void

    @StateObject private var camera = CameraController()
    private let remover = BackgroundRemovalService()
    private let store = StickerStore.shared

    @State private var captured: UIImage?     // 촬영 원본
    @State private var cutout: UIImage?       // 풀프레임 배경 제거 결과
    @State private var errorMessage: String?
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let captured {
                ScanRevealView(
                    original: captured,
                    cutout: cutout,
                    onCatch: { if let cutout { catchSticker(cutout) } },
                    onRetake: { resetToCamera() }
                )
                .transition(.opacity)
            } else {
                switch camera.status {
                case .denied: deniedView
                case .failed: failedView
                case .ready:  captureView
                default:      ProgressView().tint(.white)
                }
            }

            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .task { await camera.requestAccessAndConfigure() }
        .onDisappear { camera.stopSession() }
        .alert("안내", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var captureView: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()

            VStack {
                HStack {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .padding(16)
                    }
                    Spacer()
                }
                Spacer()
                Button(action: capture) {
                    Circle()
                        .fill(.white)
                        .frame(width: 76, height: 76)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 4).frame(width: 92, height: 92))
                }
                .padding(.bottom, 48)
            }
        }
    }

    private var failedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text("카메라를 시작할 수 없어요")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Button("다시 시도") {
                Task { await camera.requestAccessAndConfigure() }
            }
            .buttonStyle(.borderedProminent)
            Button("닫기") { onClose() }
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
    }

    private var deniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.metering.none")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.7))
            Text("카메라 권한이 필요해요")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("설정에서 카메라 접근을 켜주세요.")
                .foregroundStyle(.white.opacity(0.7))
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("닫기") { onClose() }
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
    }

    private func capture() {
        withAnimation(.easeIn(duration: 0.05)) { flash = true }
        withAnimation(.easeOut(duration: 0.35).delay(0.05)) { flash = false }
        Task {
            do {
                let photo = try await camera.capturePhoto()
                withAnimation(.easeInOut(duration: 0.2)) { captured = photo }
                let cut = try await remover.removeBackground(from: photo)
                cutout = cut
            } catch BackgroundRemovalError.noSubject {
                resetToCamera()
                errorMessage = "피사체를 찾지 못했어요. 다시 찍어볼까요?"
            } catch {
                resetToCamera()
                errorMessage = "촬영에 실패했어요. 다시 시도해주세요."
            }
        }
    }

    private func resetToCamera() {
        withAnimation(.easeInOut(duration: 0.2)) { captured = nil }
        cutout = nil
    }

    private func catchSticker(_ image: UIImage) {
        do {
            let sticker = try store.save(image: image)
            onCatch(sticker)
            onClose()
        } catch {
            errorMessage = "저장에 실패했어요."
        }
    }
}
