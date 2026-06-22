import SwiftUI
import PhotosUI

/// 촬영 플로우 상태(촬영 사진/누끼/에러). View의 @State 대신 관찰 가능한 클래스로 둬,
/// escaping Task 안에서의 상태 변경이 화면에 확실히 반영되게 한다.
@MainActor
final class CameraFlowModel: ObservableObject {
    @Published var captured: UIImage?
    @Published var cutout: UIImage?
    @Published var errorMessage: String?
    @Published var flash = false

    private var saving = false
    private let remover = BackgroundRemovalService()
    private let repo = CatchRepository.shared

    var isCapturing: Bool { captured != nil }

    /// 셔터: 촬영 → 즉시 스캔 화면 전환 → 백그라운드 누끼.
    func capture(using camera: CameraController) {
        withAnimation(.easeIn(duration: 0.05)) { flash = true }
        withAnimation(.easeOut(duration: 0.35).delay(0.05)) { flash = false }
        Task {
            do {
                let photo = try await camera.capturePhoto()
                withAnimation(.easeInOut(duration: 0.2)) { captured = photo }
                cutout = try await remover.removeBackground(from: photo)
            } catch BackgroundRemovalError.noSubject {
                reset(); errorMessage = String(localized: "피사체를 찾지 못했어요. 다시 찍어볼까요?")
            } catch {
                reset(); errorMessage = String(localized: "촬영 실패: \(error.localizedDescription)")
            }
        }
    }

    /// 사진첩에서 고른 사진으로 스티커 만들기 — 촬영과 동일한 누끼 플로우.
    func capturePicked(_ image: UIImage) {
        Task {
            do {
                let photo = image.orientationNormalized()
                withAnimation(.easeInOut(duration: 0.2)) { captured = photo }
                cutout = try await remover.removeBackground(from: photo)
            } catch BackgroundRemovalError.noSubject {
                reset(); errorMessage = String(localized: "피사체를 찾지 못했어요. 다른 사진을 골라볼까요?")
            } catch {
                reset(); errorMessage = String(localized: "처리 실패: \(error.localizedDescription)")
            }
        }
    }

    /// 카메라로 복귀(촬영/누끼 비움).
    func reset() {
        withAnimation(.easeInOut(duration: 0.2)) { captured = nil }
        cutout = nil
    }

    /// Catch: 로컬 즉시 저장 → 항아리로(업로드는 백그라운드).
    func catchSticker(_ image: UIImage, onCatch: @escaping (CloudCatch) -> Void) {
        guard !saving else { return }
        saving = true
        Task {
            let cloud = try? await repo.capture(image: image)
            saving = false
            if let cloud {
                reset()
                onCatch(cloud)
            } else {
                errorMessage = String(localized: "저장에 실패했어요.")
            }
        }
    }
}

/// SETLOG 카메라 톤 — 라운드 인셋 프리뷰 + 셔터.
///
/// ⚠️ 이 뷰는 가로 페이저(ScrollView+paging)의 자식이라, 한 번 렌더된 뒤 `flow`의 상태 변경에
/// body를 다시 그리지 않는다. 따라서 **촬영 결과에 따라 화면을 바꾸는 책임을 여기 두면 안 된다.**
/// 스캔/누끼(ScanRevealView)·알럿·플래시는 모두 MainContainerView가 컨테이너 오버레이로 그린다.
/// 여기서는 라이브 카메라/권한 상태 UI만 담당하고, 셔터는 `flow.capture(using:)`만 호출한다.
struct CameraFlowView: View {
    @ObservedObject var camera: CameraController
    @ObservedObject var flow: CameraFlowModel
    var onClose: () -> Void
    var onPickPhoto: () -> Void = {}   // 사진첩 피커는 컨테이너가 띄움(페이저 자식 재렌더 한계 회피)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.status {
            case .denied: deniedView
            case .failed: failedView
            default:      captureView   // UI는 즉시 표시, 라이브 영상만 페이드
            }
        }
    }

    private var captureView: some View {
        ZStack(alignment: .top) {
            // 프리뷰 프레임 — 검정 배경 + 라이브 영상(준비되면 페이드) + 라임 테두리.
            ZStack {
                Color.black
                CameraPreview(session: camera.session)
                    .opacity(camera.status == .ready ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: camera.status)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Theme.lime, lineWidth: 2)
            )
            .padding(.horizontal, 12)
            .padding(.top, deviceSafeAreaTop)   // 노치/다이나믹아일랜드 아래로
            .padding(.bottom, 118)

            // 셔터 + 우측 전/후면 플립
            VStack {
                Spacer()
                ZStack {
                    Button(action: { flow.capture(using: camera) }) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                            Circle().fill(.white).frame(width: 62, height: 62)
                        }
                    }
                    .disabled(camera.status != .ready)
                    .opacity(camera.status == .ready ? 1 : 0.5)
                    HStack {
                        // 셔터 왼쪽 — 사진첩에서 골라 바로 스티커로(피커는 컨테이너가 표시).
                        Button { onPickPhoto() } label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .liquidGlass(Circle(), interactive: true)
                        }
                        .padding(.leading, 40)
                        Spacer()
                        Button {
                            camera.flip()
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
            Button("다시 시도") { Task { await camera.prepare() } }
                .buttonStyle(.borderedProminent).tint(Theme.coral)
            Button("닫기") { onClose() }.foregroundStyle(.white.opacity(0.7))
        }.padding()
    }
}
