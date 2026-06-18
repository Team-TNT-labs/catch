import SwiftUI

/// SETLOG식 메인 — camera / jar / friends 가로 스와이프 + Liquid Glass 바.
struct MainContainerView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var holder = SceneHolder()
    @StateObject private var camera = CameraController()

    @State private var mode: CatchMode = .jar
    @State private var capturing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // 가로 스와이프 페이저: camera | jar | friends
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    page(.camera) {
                        CameraFlowView(
                            camera: camera,
                            capturing: $capturing,
                            onCatch: { c in
                                Task { await holder.add(c) }
                                goTo(.jar)
                            },
                            onClose: { goTo(.jar) }
                        )
                    }
                    page(.jar) {
                        HomeView(holder: holder).environmentObject(auth)
                    }
                    page(.profile) {
                        ProfilePageView().environmentObject(auth)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(.center)   // 첫 진입을 가운데(jar)로
            .scrollPosition(id: Binding(get: { mode }, set: { if let v = $0 { mode = v } }))
            // jar에선 스와이프 잠금(스티커 드래그 보호). 이동은 세그먼트 탭으로.
            .scrollDisabled(mode == .jar || holder.isGrabbing || capturing)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .onChange(of: mode) { _, m in
                if m == .camera {
                    // 전환 애니메이션이 끝난 뒤 시작 — 검정 먼저 뜨고 로딩(첫 진입 렉 방지)
                    Task {
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        if mode == .camera { await camera.requestAccessAndConfigure() }
                    }
                } else {
                    camera.stopSession()
                }
            }

            // 하단 Liquid Glass 세그먼트
            if !capturing {
                SetlogBottomBar(mode: $mode)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: mode)
        .animation(.easeInOut(duration: 0.25), value: capturing)
    }

    /// 한 페이지를 부드러운 스크롤 트랜지션(살짝 페이드+스케일)으로 감싼다.
    private func page<Content: View>(_ id: CatchMode, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .containerRelativeFrame(.horizontal)
            .id(id)
            .scrollTransition(.interactive) { view, phase in
                view
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
            }
    }

    private func goTo(_ m: CatchMode) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { mode = m }
    }
}
