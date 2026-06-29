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
    @Published var folders: [Folder] = []     // 내 폴더(루트에서 모양 노드로 표시)
    @Published var currentFolder: Folder?     // nil = 루트(미분류 + 폴더들)
    @Published var navToken = 0               // 폴더 진입/이탈마다 +1 → 뷰가 확장 전환 재생
    @Published var folderToEdit: Folder?      // 꾹 눌러 편집 / + 새 폴더 시트
    private(set) var creatingFolderId: UUID?  // folderToEdit가 새 폴더면 그 임시 id

    func isCreating(_ folder: Folder) -> Bool { creatingFolderId == folder.id }
    @Published var ejectHovering = false      // 폴더 안: 스티커가 뒤로가기 위에 올라옴
    @Published var showSettings = false       // 상단 ellipsis → 설정 시트(컨테이너에서 표시)

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
        scene.onOpenFolder = { [weak self] id in
            Task { await self?.enterFolder(id) }
        }
        scene.onDropOnFolder = { [weak self] sid, fid in
            self?.dropSticker(sid, into: fid)
        }
        scene.onEditFolder = { [weak self] id in
            self?.folderToEdit = self?.folders.first { $0.id == id }
        }
        scene.onEjectSticker = { [weak self] sid in
            self?.ejectSticker(sid)
        }
        scene.onEjectHover = { [weak self] on in
            self?.ejectHovering = on
        }
    }

    /// 스티커를 폴더 밖(미분류)으로. 노드는 씬에서 빨려 나가는 중.
    private func ejectSticker(_ stickerId: UUID) {
        byId[stickerId] = nil
        catches.removeAll { $0.id == stickerId }
        repo.setFolder(stickerId, folderId: nil)
        Task { await FolderRepository.shared.assign(catchId: stickerId, folderId: nil) }
    }

    // MARK: - 폴더 네비게이션

    func enterFolder(_ id: UUID) async {
        currentFolder = folders.first { $0.id == id }
        scene.ejectEnabled = true   // 폴더 안: 뒤로가기로 빼기 가능
        navToken += 1               // 확장 전환 재생
        await reload(folderId: id)
    }

    func exitToRoot() async {
        currentFolder = nil
        scene.ejectEnabled = false
        ejectHovering = false
        navToken += 1               // 확장 전환 재생
        await reload(folderId: nil)
    }

    /// `+` → 편집과 동일한 시트를 "새 폴더"로 띄운다(아직 서버에 없는 임시 폴더).
    func beginCreateFolder() {
        let placeholder = Folder(id: UUID(), name: "새 폴더", isPublic: true, sort: 0,
                                 shape: 0, color: 0, labelColor: 0)
        creatingFolderId = placeholder.id
        folderToEdit = placeholder
    }

    /// 새 폴더 생성(모양/색/레이블 포함).
    func createFolder(name: String, shape: Int?, color: Int?, labelColor: Int?) async {
        guard let f0 = await FolderRepository.shared.create(name: name) else { return }
        await FolderRepository.shared.update(f0.id, name: name, shape: shape, color: color, labelColor: labelColor)
        var f = f0; f.shape = shape; f.color = color; f.labelColor = labelColor
        folders.append(f)
        if currentFolder == nil {
            scene.addFolder(id: f.id, name: name, shape: shape, color: color, labelColor: labelColor)
        }
    }

    func updateFolder(_ id: UUID, name: String, shape: Int?, color: Int?, labelColor: Int?) async {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name; folders[i].shape = shape; folders[i].color = color; folders[i].labelColor = labelColor
        if currentFolder?.id == id { currentFolder = folders[i] }
        await FolderRepository.shared.update(id, name: name, shape: shape, color: color, labelColor: labelColor)
        if currentFolder == nil {   // 루트 노드 갱신(새 모양/색/이름)
            scene.removeFolderNode(id: id)
            scene.addFolder(id: id, name: name, shape: shape, color: color, labelColor: labelColor)
        }
    }

    func deleteFolder(_ id: UUID) async {
        await FolderRepository.shared.delete(id)
        folders.removeAll { $0.id == id }
        folderToEdit = nil
        if currentFolder?.id == id {   // 보고 있던 폴더를 지웠으면 루트로
            await exitToRoot()
        } else {
            scene.removeFolderNode(id: id)
        }
    }

    /// 스티커를 폴더에 담는다(노드는 씬에서 빨려 들어가는 중). 데이터/서버 배정 + 현재 목록에서 제거.
    private func dropSticker(_ stickerId: UUID, into folderId: UUID) {
        byId[stickerId] = nil
        catches.removeAll { $0.id == stickerId }
        repo.setFolder(stickerId, folderId: folderId)   // 로컬 즉시
        Task { await FolderRepository.shared.assign(catchId: stickerId, folderId: folderId) }
    }

    func loadMineIfNeeded() async {
        guard !loadedOnce else { return }
        loadedOnce = true
        folders = await FolderRepository.shared.listMine()
        reconcileOrphans()
        await reload(folderId: nil)
    }

    /// 백업 복원 후 전체 새로고침.
    func reloadAll() async {
        await exitToRoot()
        folders = await FolderRepository.shared.listMine()
        reconcileOrphans()
        await reload(folderId: nil)
    }

    /// 존재하지 않는 폴더(예: 옛 서버 폴더)를 가리키는 스티커는 미분류(루트)로 되돌려 항아리에서 다시 보이게.
    private func reconcileOrphans() {
        let ids = Set(folders.map { $0.id })
        for c in repo.localCatches() where c.folderId != nil && !ids.contains(c.folderId!) {
            repo.setFolder(c.id, folderId: nil)
        }
    }

    func reload(folderId: UUID?) async {
        scene.clearAll()
        byId.removeAll()
        catches.removeAll()
        isLoading = false

        // 루트면 폴더들을 모양 노드로 먼저 투하.
        if folderId == nil {
            for f in folders {
                scene.addFolder(id: f.id, name: f.name, shape: f.shape, color: f.color, labelColor: f.labelColor)
                try? await Task.sleep(nanoseconds: 45_000_000)
            }
        }

        // 해당 폴더(루트=미분류) 스티커 — 로컬 즉시.
        let local = repo.localCatches(inFolder: folderId)
        catches = local
        for c in local {
            byId[c.id] = c
            try? await Task.sleep(nanoseconds: 70_000_000)
            await spawn(c)
        }
        // 백그라운드: 클라우드와 병합해 다른 기기 캐치 추가.
        let added = await repo.refreshFromCloud()
        for c in added where c.folderId == folderId {
            guard byId[c.id] == nil else { continue }
            byId[c.id] = c
            catches.append(c)
            await spawn(c)
        }
        isEmpty = byId.isEmpty && (folderId != nil || folders.isEmpty)
    }

    func add(_ c: CloudCatch) async {
        if currentFolder != nil { await exitToRoot() }   // 새 캐치는 루트(미분류)로
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
        // Phase1 egress 절감: 항아리 표시(≤126px)엔 본문 썸네일(256px)로 충분 — 원본 다운로드 생략.
        guard let body = await repo.bodyImage(for: c) else { return }
        // 무거운 테두리 생성(블러+드로잉)은 백그라운드에서 — 메인스레드 렉 방지.
        let prepared = await Task.detached(priority: .userInitiated) {
            body.whiteStickerBordered()
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
    @EnvironmentObject private var pro: ProStore
    @ObservedObject var holder: SceneHolder
    @State private var showPaywall = false
    @State private var enterScale: CGFloat = 1   // 폴더 진입/이탈 시 항아리가 확장되는 전환

    var body: some View {
        ZStack(alignment: .top) {
            // 폴더 전환 시 항아리(씬+그리드)가 작게 시작해 확 펼쳐지는 느낌.
            ZStack {
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
            }
            .scaleEffect(enterScale)
            .opacity(Double(min(1, max(0, (enterScale - 0.8) / 0.2))))

            topBar
                .padding(.top, deviceSafeAreaTop + 4)
        }
        .animation(.easeInOut(duration: 0.45), value: holder.isGrid)
        // 폴더 진입/이탈마다 0.8 → 1로 스프링 확장(살짝 오버슈트).
        .onChange(of: holder.navToken) { _, _ in
            enterScale = 0.8
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { enterScale = 1 }
        }
        .task {
            // 하단 커스텀 툴바(가운데 알약) 충돌 바디 설정 — 스티커가 바에 안 가려지게.
            // 실제 보이는 알약 치수(SetlogBottomBar)에서 계산 → 탭 수가 바뀌어도 자동 정렬.
            holder.scene.toolbarBarrier = (width: SetlogBottomBar.pillWidth, height: SetlogBottomBar.pillHeight, bottomMargin: deviceSafeAreaBottom + 6)
            await holder.loadMineIfNeeded()
        }
        // 폴더 추가/편집 시트·삭제 확인은 컨테이너(MainContainerView)에서.
        .sheet(isPresented: $showPaywall) { PaywallView().environmentObject(pro) }
    }

    /// 그리드 보기 — 고정 크기 셀의 스크롤 격자(탭→포커스, 길게눌러 삭제).
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 14) {
                // 루트면 폴더 먼저(탭→진입, 길게눌러 편집).
                if holder.currentFolder == nil {
                    ForEach(holder.folders) { f in
                        Button { Task { await holder.enterFolder(f.id) } } label: {
                            Image(uiImage: FolderShape.resolve(f.shape, id: f.id)
                                .image(name: f.name, fill: FolderPalette.uiColor(f.color),
                                       label: FolderLabel.uiColor(fill: f.color)))
                                .resizable().scaledToFit()
                                .padding(8)
                                .frame(height: 116)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { holder.folderToEdit = f } label: { Label("편집", systemImage: "pencil") }
                            Button(role: .destructive) { Task { await holder.deleteFolder(f.id) } } label: { Text("삭제") }
                        }
                    }
                }
                ForEach(holder.catches) { c in
                    Button { Task { await holder.focus(c.id) } } label: {
                        BorderedStickerImage(path: c.bodyPath ?? c.imagePath)
                            .padding(10)
                            .frame(height: 116)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await holder.deleteFromGrid(c.id) }
                        } label: { Text("삭제") }   // 아이콘 빼서 전역 tint와 색 불일치 방지(빨강 통일)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, deviceSafeAreaTop + 116)
            .padding(.bottom, deviceSafeAreaBottom + 96)
        }
        .scrollIndicators(.hidden)
        // 검정 대신 항아리 배경(사진/단색/기본)을 깔아 Pro 배경이 그리드에서도 유지되게 한다.
        .background(JarBackdrop())
    }

    private var topBar: some View {
        ZStack {
            // 폴더 안: 제목 가운데 정렬
            if let folder = holder.currentFolder {
                Text(folder.name).font(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                    .frame(maxWidth: 180)
            }
            HStack {
                // 루트: 로고 / 폴더 안: 뒤로가기
                if holder.currentFolder != nil {
                    Button { Task { await holder.exitToRoot() } } label: {
                        Image(systemName: holder.ejectHovering ? "arrow.up.left.circle.fill" : "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(holder.ejectHovering ? .black : .white)
                            .frame(width: 44, height: 44)
                            .background(holder.ejectHovering ? Theme.lime : .clear, in: Circle())
                            .liquidGlass(Circle(), interactive: true)
                            .scaleEffect(holder.ejectHovering ? 1.25 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: holder.ejectHovering)
                    }
                } else if UIImage(named: "CatchLogo") != nil {
                    Image("CatchLogo").renderingMode(.template).resizable().scaledToFit()
                        .foregroundStyle(Theme.lime).frame(height: 26)
                } else {
                    Text("catch").font(.system(size: 24, weight: .heavy)).foregroundStyle(Theme.lime)
                }
                Spacer()
                HStack(spacing: 10) {
                    // 개발자 소개 + Pro 시트 (루트에서만 — 폴더 안엔 폴더 편집 ellipsis가 따로 있음)
                    if holder.currentFolder == nil {
                        Button { holder.showSettings = true } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).liquidGlass(Circle(), interactive: true)
                        }
                    }
                    // 보기 모드 — 누를 때마다 중력 ↔ 그리드
                    Button { holder.cycleMode() } label: {
                        Image(systemName: holder.mode.icon)
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).liquidGlass(Circle(), interactive: true)
                    }
                    // 루트: 폴더 추가 / 폴더 안: 현재 폴더 편집
                    if holder.currentFolder == nil {
                        Button {
                            if pro.isPro || holder.folders.count < ProStore.freeFolderLimit {
                                holder.beginCreateFolder()
                            } else { showPaywall = true }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).liquidGlass(Circle(), interactive: true)
                        }
                    } else {
                        Button { holder.folderToEdit = holder.currentFolder } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).liquidGlass(Circle(), interactive: true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
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

/// 그리드 보기 배경 — 항아리 배경(사진/단색/기본 그라데이션)을 그대로 깔아 물리 씬을 덮는다.
/// StickerScene.rebuildBackground와 동일한 우선순위(사진 → 단색 → 기본 그라데이션). (Android jarBackground 대응)
struct JarBackdrop: View {
    @ObservedObject private var store = JarBackgroundStore.shared

    var body: some View {
        Group {
            if let photo = store.photo {
                GeometryReader { geo in
                    Image(uiImage: photo)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else if let color = store.uiColor {
                Color(color)
            } else {
                LinearGradient(colors: [Color(Theme.sceneTop), Color(Theme.sceneBottom)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}
