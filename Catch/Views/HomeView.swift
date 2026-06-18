import SwiftUI
import SpriteKit

/// 항아리 보기 모드 — 중력(물리) ↔ 그리드(정렬).
enum JarMode: CaseIterable {
    case gravity, grid
    /// 버튼에 표시할 아이콘(탭하면 전환될 모드를 암시).
    var icon: String {
        switch self {
        case .gravity: return "square.grid.2x2"        // 탭 → 그리드
        case .grid:    return "circle.grid.3x3.fill"   // 탭 → 중력
        }
    }
}

/// 물리 씬 + 클라우드 수집 로딩/삭제.
@MainActor
final class SceneHolder: ObservableObject {
    let scene: StickerScene
    private let repo = CatchRepository.shared

    @Published var isLoading = false
    @Published var isEmpty = false
    @Published var isGrabbing = false   // 스티커 드래그 중 → 페이지 스와이프 잠금
    @Published var mode: JarMode = .gravity   // 중력 / 둥둥 / 그리드
    @Published private(set) var catches: [CloudCatch] = []   // 그리드 표시용(추가 순서)
    @Published var focused: CloudCatch?       // 탭한 스티커(포커스 프리뷰)
    @Published var focusedImage: UIImage?
    @Published var pendingDeleteId: UUID?     // 꾹 눌러 삭제 요청 → 확인 대기

    var isGrid: Bool { mode == .grid }

    /// 탭할 때마다 다음 모드로 순환(중력 → 둥둥 → 그리드 → …).
    func cycleMode() {
        let all = JarMode.allCases
        let next = all[((all.firstIndex(of: mode) ?? 0) + 1) % all.count]
        setMode(next)
    }

    func setMode(_ m: JarMode) {
        mode = m
        // 실제 스티커 노드가 움직여 정렬/해제(스크롤 격자는 그 위로 페이드인).
        switch m {
        case .grid:    scene.arrangeGrid()
        case .gravity: scene.releaseGrid()
        }
    }

    func focus(_ id: UUID) async {
        guard let c = byId[id], let img = await repo.displayImage(for: c) else { return }
        // 씬과 동일하게 흰색 테두리를 입혀서 보여준다.
        focusedImage = img.whiteStickerBordered().bordered
        focused = c
    }

    func dismissFocus() {
        focused = nil
        focusedImage = nil
    }

    private var byId: [UUID: CloudCatch] = [:]
    private var loadedOnce = false

    init() {
        let scene = StickerScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        self.scene = scene
        scene.onRequestDelete = { [weak self] id in
            self?.pendingDeleteId = id   // 즉시 삭제 X — 확인 다이얼로그로
        }
        scene.onGrabChanged = { [weak self] grabbing in
            self?.isGrabbing = grabbing
        }
        scene.onTapCatch = { [weak self] id in
            Task { await self?.focus(id) }
        }
    }

    func loadMineIfNeeded() async {
        guard !loadedOnce else { return }
        loadedOnce = true
        await reload(folderId: nil)
    }

    func reload(folderId: UUID?) async {
        scene.clearAll()
        byId.removeAll()
        catches.removeAll()
        // 로컬에서 즉시 표시(네트워크 대기 없음)
        let local = repo.localCatches(folderId: folderId)
        isEmpty = local.isEmpty
        isLoading = false
        catches = local
        for c in local {
            byId[c.id] = c
            try? await Task.sleep(nanoseconds: 70_000_000)
            await spawn(c)
        }
        // 백그라운드: 클라우드와 병합해 다른 기기 캐치 추가
        let added = await repo.refreshFromCloud()
        for c in added where folderId == nil || c.folderId == folderId {
            guard byId[c.id] == nil else { continue }
            byId[c.id] = c
            catches.append(c)
            await spawn(c)
        }
        if !byId.isEmpty { isEmpty = false }
    }

    func add(_ c: CloudCatch) async {
        byId[c.id] = c
        catches.append(c)
        isEmpty = false
        await spawn(c)
    }

    /// 그리드에서 개별 삭제(씬 노드 + 데이터 + 서버).
    func deleteFromGrid(_ id: UUID) async {
        scene.removeNode(id: id)
        await remove(id)
    }

    /// 꾹 눌러 삭제 요청을 확정(연출 후 삭제). id를 명시로 받아 다이얼로그 dismiss와의 레이스 회피.
    func confirmDelete(_ id: UUID) async {
        pendingDeleteId = nil
        scene.vanish(id: id)
        await remove(id)
    }

    func cancelDelete() { pendingDeleteId = nil }

    private func spawn(_ c: CloudCatch) async {
        guard let display = await repo.displayImage(for: c) else { return }
        let body = await repo.bodyImage(for: c) ?? display
        // 무거운 테두리 생성(블러+드로잉)은 백그라운드에서 — 메인스레드 렉 방지.
        let prepared = await Task.detached(priority: .userInitiated) {
            display.whiteStickerBordered()
        }.value
        scene.addCatch(id: c.id, bordered: prepared.bordered, working: prepared.working, body: body)
    }

    private func remove(_ id: UUID) async {
        guard let c = byId[id] else { return }
        byId[id] = nil
        catches.removeAll { $0.id == id }
        await repo.delete(c)
        if byId.isEmpty { isEmpty = true }
    }
}

/// 메인(jar) — 물리 항아리 + 카운트 + 폴더 칩. 상/하단 바는 컨테이너가 그린다.
struct HomeView: View {
    @EnvironmentObject private var auth: AuthService
    @ObservedObject var holder: SceneHolder

    @State private var folders: [Folder] = []
    @State private var selectedFolder: UUID?
    @State private var showFolders = false

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: holder.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            // 그리드 보기 — 작아지지 않게 고정 크기 스크롤 격자(물리 일시정지 위에 덮음).
            if holder.isGrid {
                gridView.transition(.opacity)
            }

            if holder.isLoading {
                CatchLoader()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 10) {
                topBar
                folderBar
            }
            .padding(.top, deviceSafeAreaTop + 4)
        }
        .animation(.easeInOut(duration: 0.45), value: holder.isGrid)
        .task {
            // 하단 커스텀 툴바(가운데 알약) 충돌 바디 설정 — 스티커가 바에 안 가려지게.
            holder.scene.toolbarBarrier = (width: 226, height: 72, bottomMargin: deviceSafeAreaBottom + 6)
            await holder.loadMineIfNeeded()
            folders = await FolderRepository.shared.listMine()
        }
        .sheet(isPresented: $showFolders) {
            FoldersView(onChanged: {
                Task {
                    folders = await FolderRepository.shared.listMine()
                    await holder.reload(folderId: selectedFolder)
                }
            })
        }
        // 삭제 확인 다이얼로그는 컨테이너(MainContainerView)에서 — 페이저 자식인 HomeView는
        // holder 변경에 재렌더되지 않아 여기 붙이면 안 뜬다.
    }

    /// 그리드 보기 — 고정 크기 셀의 스크롤 격자(탭→포커스, 길게눌러 삭제).
    /// 그리드 보기 — 고정 크기 셀의 스크롤 격자(탭→포커스, 길게눌러 삭제).
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 14) {
                ForEach(holder.catches) { c in
                    Button { Task { await holder.focus(c.id) } } label: {
                        BorderedStickerImage(path: c.imagePath)
                            .padding(10)
                            .frame(height: 116)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await holder.deleteFromGrid(c.id) }
                        } label: { Label("삭제", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, deviceSafeAreaTop + 116)
            .padding(.bottom, deviceSafeAreaBottom + 96)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("all", selected: selectedFolder == nil) {
                    selectedFolder = nil
                    Task { await holder.reload(folderId: nil) }
                }
                ForEach(folders) { f in
                    chip(f.name, selected: selectedFolder == f.id) {
                        selectedFolder = f.id
                        Task { await holder.reload(folderId: f.id) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var topBar: some View {
        HStack {
            if UIImage(named: "CatchLogo") != nil {
                Image("CatchLogo").resizable().scaledToFit().frame(height: 26)
            } else {
                Text("catch").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.lime)
            }
            Spacer()
            HStack(spacing: 10) {
                // 보기 모드 — 누를 때마다 중력 → 둥둥 → 그리드 순환
                Button { holder.cycleMode() } label: {
                    Image(systemName: holder.mode.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .liquidGlass(Circle(), interactive: true)
                }
                // 메뉴
                Menu {
                    Button { showFolders = true } label: { Label("폴더 관리", systemImage: "folder") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .liquidGlass(Circle(), interactive: true)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private func chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(selected ? .black : Theme.muted)
                .padding(.horizontal, 16).frame(height: 32)
                .background(selected ? Theme.coral : Theme.surface, in: Capsule())
        }
    }

}

/// 탭한 스티커를 블러 배경 위에 중앙·확대로 화려하게.
struct FocusedStickerView: View {
    let image: UIImage
    var onDismiss: () -> Void
    @State private var appear = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(appear ? 1 : 0)

            // 화려한 라임 글로우
            Circle()
                .fill(RadialGradient(colors: [Theme.lime.opacity(0.55), .clear],
                                     center: .center, startRadius: 8, endRadius: 280))
                .frame(width: 560, height: 560)
                .blur(radius: 36)
                .scaleEffect(appear ? 1 : 0.5)
                .opacity(appear ? 1 : 0)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 380)
                .shadow(color: Theme.lime.opacity(0.6), radius: 26)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
                .scaleEffect(appear ? 1.12 : 0.6)
                .rotationEffect(.degrees(appear ? 0 : -8))
                .opacity(appear ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appear = true }
        }
    }
}
