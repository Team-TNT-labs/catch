import SwiftUI

/// SETLOG식 메인 — camera / jar / friends 가로 스와이프 + Liquid Glass 바.
struct MainContainerView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var holder = SceneHolder()
    @StateObject private var camera = CameraController()

    @State private var mode: CatchMode = .jar
    @State private var capturing = false
    @State private var showSettings = false
    @State private var showSearch = false

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
                    page(.friends) {
                        FeedView()
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { mode }, set: { if let v = $0 { mode = v } }))
            .scrollDisabled(holder.isGrabbing || capturing)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .onChange(of: mode) { _, m in
                if m == .camera { Task { await camera.requestAccessAndConfigure() } }
                else { camera.stopSession() }
            }

            // 상단 로고 바 (jar 모드)
            if mode == .jar && !capturing {
                VStack { topBar; Spacer() }
                    .transition(.opacity)
            }

            // 하단 Liquid Glass 바
            if !capturing {
                SetlogBottomBar(
                    mode: $mode,
                    rightIcon: "magnifyingglass",
                    onLeft: { showSettings = true },
                    onRight: { showSearch = true }
                )
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: mode)
        .animation(.easeInOut(duration: 0.25), value: capturing)
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(auth) }
        .sheet(isPresented: $showSearch) { UserSearchView() }
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

    private var topBar: some View {
        HStack {
            if UIImage(named: "CatchLogo") != nil {
                Image("CatchLogo").resizable().scaledToFit().frame(height: 26)
            } else {
                Text("catch").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.lime)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }
}
