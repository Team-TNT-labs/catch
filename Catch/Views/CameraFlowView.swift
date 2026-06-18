import SwiftUI

/// SETLOG 카메라 톤 — 라운드 인셋 프리뷰 + 세로 시계 + 셔터. 촬영 후 스캔 누끼 오버레이.
struct CameraFlowView: View {
    @ObservedObject var camera: CameraController
    @Binding var capturing: Bool
    var onCatch: (CloudCatch) -> Void
    var onClose: () -> Void

    private let remover = BackgroundRemovalService()
    private let repo = CatchRepository.shared

    @State private var captured: UIImage?
    @State private var cutout: UIImage?
    @State private var errorMessage: String?
    @State private var flash = false
    @State private var saving = false

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
                case .configuring: CatchLoader()
                case .unknown: Color.black   // 아직 시작 안 함(다른 탭에 있을 때) → 로더 X
                }
            }

            if flash { Color.white.ignoresSafeArea().transition(.opacity) }
        }
        .onChange(of: captured == nil) { _, isNil in capturing = !isNil }
        .alert("안내", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var captureView: some View {
        ZStack(alignment: .top) {
            // 프리뷰 — 안전영역 안(바깥은 검정) + 좌우 여백 + 라임 테두리
            CameraPreview(session: camera.session)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Theme.lime, lineWidth: 2)
                )
                .padding(.horizontal, 12)
                .padding(.top, deviceSafeAreaTop)   // 노치/다이나믹아일랜드 아래로
                .padding(.bottom, 118)

            // X 닫기
            HStack {
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .liquidGlass(Circle(), interactive: true)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, deviceSafeAreaTop + 8)

            // 셔터 + 우측 전/후면 플립
            VStack {
                Spacer()
                ZStack {
                    Button(action: capture) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                            Circle().fill(.white).frame(width: 62, height: 62)
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            Task { await camera.flip() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .liquidGlass(Circle(), interactive: true)
                        }
                        .padding(.trailing, 40)
                    }
                }
                .padding(.bottom, 150)
            }
        }
    }

    private var deniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.metering.none").font(.system(size: 48)).foregroundStyle(.white.opacity(0.7))
            Text("카메라 권한이 필요해요").font(.title3.bold()).foregroundStyle(.white)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.buttonStyle(.borderedProminent).tint(Theme.coral)
            Button("닫기") { onClose() }.foregroundStyle(.white.opacity(0.7))
        }.padding()
    }

    private var failedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.white.opacity(0.7))
            Text("카메라를 시작할 수 없어요").font(.title3.bold()).foregroundStyle(.white)
            Button("다시 시도") { Task { await camera.requestAccessAndConfigure() } }
                .buttonStyle(.borderedProminent).tint(Theme.coral)
            Button("닫기") { onClose() }.foregroundStyle(.white.opacity(0.7))
        }.padding()
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
                resetToCamera(); errorMessage = "피사체를 찾지 못했어요. 다시 찍어볼까요?"
            } catch {
                resetToCamera(); errorMessage = "촬영에 실패했어요. 다시 시도해주세요."
            }
        }
    }

    private func resetToCamera() {
        withAnimation(.easeInOut(duration: 0.2)) { captured = nil }
        cutout = nil
    }

    private func catchSticker(_ image: UIImage) {
        guard !saving else { return }
        saving = true
        Task {
            // 로컬에 즉시 저장 → 바로 항아리로(업로드는 백그라운드)
            let cloud = try? await repo.capture(image: image)
            saving = false
            if let cloud {
                resetToCamera()   // captured/cutout 비워 capturing=false → 하단 바 복귀
                onCatch(cloud)
            } else {
                errorMessage = "저장에 실패했어요."
            }
        }
    }
}
