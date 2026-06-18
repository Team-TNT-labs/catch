import SwiftUI

/// SETLOG식 메인 — camera / jar / friends 가로 스와이프 + Liquid Glass 바.
struct MainContainerView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var holder = SceneHolder()
    @StateObject private var camera = CameraController()

    // 스크롤 위치 = 단일 진실원천(표준 옵셔널 바인딩).
    @State private var page: CatchMode? = .jar
    @State private var capturing = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // 가로 페이저 — jar를 가운데에 둬 camera/profile 양쪽에서 드래그하면 jar로.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    pageView(.camera) {
                        CameraFlowView(
                            camera: camera,
                            isActive: page == .camera,
                            capturing: $capturing,
                            onCatch: { c in
                                Task { await holder.add(c) }
                                goTo(.jar)
                            },
                            onClose: { goTo(.jar) }
                        )
                    }
                    pageView(.jar) {
                        HomeView(holder: holder).environmentObject(auth)
                    }
                    pageView(.profile) {
                        ProfilePageView().environmentObject(auth)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .defaultScrollAnchor(.center)   // 첫 진입을 가운데(jar)로
            .scrollPosition(id: $page)
            // jar에선 스와이프 잠금(스티커 드래그 보호). 이동은 세그먼트 탭으로.
            .scrollDisabled(page == .jar || holder.isGrabbing || capturing)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()

            // 하단 Liquid Glass 세그먼트
            if !capturing {
                SetlogBottomBar(selection: $page)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: page)
        .animation(.easeInOut(duration: 0.25), value: capturing)
        .task {
            // 진입 시 카메라 권한 팝업을 한 번 띄운다(세션은 카메라 페이지에서 시작).
            await camera.ensurePermission()
        }
    }

    /// 한 페이지를 부드러운 스크롤 트랜지션(살짝 페이드+스케일)으로 감싼다.
    private func pageView<Content: View>(_ id: CatchMode, @ViewBuilder _ content: () -> Content) -> some View {
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
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { page = m }
    }
}
