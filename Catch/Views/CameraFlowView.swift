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
                default:      ProgressView().tint(Theme.coral)
                }
            }

            if flash { Color.white.ignoresSafeArea().transition(.opacity) }
            if saving {
                Color.black.opacity(0.55).ignoresSafeArea()
                ProgressView("catching…").tint(.white).foregroundStyle(.white)
            }
        }
        .task { await camera.requestAccessAndConfigure() }
        .onDisappear { camera.stopSession() }
        .onChange(of: captured == nil) { _, isNil in capturing = !isNil }
        .alert("안내", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var captureView: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 130)
                    .padding(.top, 4)

                // 세로 시계
                Text(timeString)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 40)
                    .position(x: 38, y: geo.size.height * 0.45)
                    .shadow(color: .black.opacity(0.4), radius: 6)

                // X 닫기
                HStack {
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                // 셔터
                VStack {
                    Spacer()
                    Button(action: capture) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                            Circle().fill(.white).frame(width: 62, height: 62)
                        }
                    }
                    .padding(.bottom, 150)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
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
            do {
                let cloud = try await repo.upload(image: image)
                saving = false
                onCatch(cloud)
            } catch {
                saving = false
                errorMessage = "저장에 실패했어요. 네트워크를 확인해주세요."
            }
        }
    }
}
