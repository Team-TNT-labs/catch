import SwiftUI

/// SETLOG식 메인 — camera / jar / friends 가로 스와이프 + Liquid Glass 바.
struct MainContainerView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var holder = SceneHolder()
    @StateObject private var camera = CameraController()
    // 촬영 플로우 상태는 컨테이너가 소유 — 페이저 자식 뷰 갱신이 막히지 않도록.
    @StateObject private var flow = CameraFlowModel()

    // 스크롤 위치 = 단일 진실원천(표준 옵셔널 바인딩).
    @State private var page: CatchMode? = .jar

    private var capturing: Bool { flow.isCapturing }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // 가로 페이저 — jar를 가운데에 둬 camera/profile 양쪽에서 드래그하면 jar로.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    pageView(.camera) {
                        CameraFlowView(camera: camera, flow: flow, onClose: { goTo(.jar) })
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
        // ⚠️ 불변식: 촬영 결과 스캔/누끼(ScanRevealView)는 반드시 여기 — 컨테이너 레벨 — 에서 그린다.
        // 가로 페이저(ScrollView+paging)의 자식 페이지(CameraFlowView)는 한 번 렌더된 뒤
        // 관찰 상태(flow.captured) 변경에 body를 다시 그리지 않아, 페이지 안에 넣으면 화면이 안 바뀐다.
        // (셔터→스캔 전환이 안 되던 버그의 근본 원인. 절대 CameraFlowView 안으로 되돌리지 말 것.)
        .overlay {
            if let captured = flow.captured {
                ScanRevealView(
                    original: captured,
                    cutout: flow.cutout,
                    onCatch: { image in
                        flow.catchSticker(image) { c in
                            Task { await holder.add(c) }
                            goTo(.jar)
                        }
                    },
                    onRetake: { flow.reset() }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
            if flow.flash { Color.white.ignoresSafeArea() }
        }
        .animation(.easeInOut(duration: 0.2), value: flow.captured != nil)
        // 스티커 상세 — 시트 대신 컨테이너 오버레이(하단 바까지 덮음). 스프링으로 팝업.
        .overlay {
            if let c = holder.focused {
                StickerDetailView(
                    catchId: c.id, imagePath: c.imagePath, ownerId: c.ownerId,
                    initialTitle: c.title, preloaded: holder.focusedImage,
                    onClose: { holder.dismissFocus() }
                )
                .transition(.scale(scale: 0.9, anchor: .center).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: holder.focused != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: page)
        .animation(.easeInOut(duration: 0.25), value: capturing)
        .alert("안내", isPresented: Binding(
            get: { flow.errorMessage != nil }, set: { if !$0 { flow.errorMessage = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(flow.errorMessage ?? "") }
        // 폴더 편집 시트 — 컨테이너 레벨(페이저 자식은 holder 변경에 재렌더 불안정).
        .sheet(item: $holder.folderToEdit) { folder in
            FolderEditView(
                folder: folder,
                onSave: { name, shape, color in
                    holder.folderToEdit = nil
                    Task { await holder.updateFolder(folder.id, name: name, shape: shape, color: color) }
                },
                onDelete: { Task { await holder.deleteFolder(folder.id) } },
                onClose: { holder.folderToEdit = nil }
            )
        }
        // 꾹 눌러 삭제 확인 — 컨테이너 레벨(페이저 자식은 holder 변경에 재렌더 안 됨).
        .confirmationDialog(
            "이 스티커를 삭제할까요?",
            isPresented: Binding(get: { holder.pendingDeleteId != nil },
                                 set: { if !$0 { holder.cancelDelete() } }),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let id = holder.pendingDeleteId { Task { await holder.confirmDelete(id) } }
            }
            Button("취소", role: .cancel) { holder.cancelDelete() }
        }
        .task { await camera.prepare() }
        .onChange(of: page, initial: true) { _, p in
            if p == .camera { camera.startSession() } else { camera.stopSession() }
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
