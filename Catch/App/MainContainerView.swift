import SwiftUI

/// SETLOG식 메인 — camera/jar 모드 전환 + 상/하단 바.
struct MainContainerView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var holder = SceneHolder()
    @StateObject private var camera = CameraController()

    @State private var mode: CatchMode = .jar
    @State private var capturing = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showFeed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // jar (항상 마운트 — 상태 유지)
            HomeView(holder: holder)
                .environmentObject(auth)
                .opacity(mode == .jar ? 1 : 0)
                .allowsHitTesting(mode == .jar)

            // camera (카메라 모드일 때만 — 세션 라이프사이클)
            if mode == .camera {
                CameraFlowView(
                    camera: camera,
                    capturing: $capturing,
                    onCatch: { c in
                        Task { await holder.add(c) }
                        withAnimation(.easeInOut(duration: 0.25)) { mode = .jar }
                    },
                    onClose: { withAnimation(.easeInOut(duration: 0.25)) { mode = .jar } }
                )
                .transition(.opacity)
            }

            // 상단 바 (jar 모드)
            if mode == .jar && !capturing {
                VStack { topBar; Spacer() }
            }

            // 하단 SETLOG 바
            if !capturing {
                SetlogBottomBar(
                    mode: $mode,
                    rightIcon: mode == .camera ? "arrow.triangle.2.circlepath" : "magnifyingglass",
                    onLeft: { showSettings = true },
                    onRight: {
                        if mode == .camera { Task { await camera.flip() } }
                        else { showSearch = true }
                    }
                )
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(auth) }
        .sheet(isPresented: $showSearch) { UserSearchView() }
        .sheet(isPresented: $showFeed) { FeedView() }
    }

    private var topBar: some View {
        HStack {
            if UIImage(named: "CatchLogo") != nil {
                Image("CatchLogo").resizable().scaledToFit().frame(height: 26)
            } else {
                Text("catch").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.lime)
            }
            Spacer()
            RoundBarButton(icon: "square.stack.3d.up.fill") { showFeed = true }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }
}
