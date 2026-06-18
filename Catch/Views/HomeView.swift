import SwiftUI
import SpriteKit

/// 물리 씬 + 클라우드 수집 로딩/삭제.
@MainActor
final class SceneHolder: ObservableObject {
    let scene: StickerScene
    private let repo = CatchRepository.shared

    @Published var isLoading = false
    @Published var isEmpty = false
    @Published var isGrabbing = false   // 스티커 드래그 중 → 페이지 스와이프 잠금

    private var byId: [UUID: CloudCatch] = [:]
    private var loadedOnce = false

    init() {
        let scene = StickerScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        self.scene = scene
        scene.onDeleteCatch = { [weak self] id in
            Task { await self?.remove(id) }
        }
        scene.onGrabChanged = { [weak self] grabbing in
            self?.isGrabbing = grabbing
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
        // 로컬에서 즉시 표시(네트워크 대기 없음)
        let local = repo.localCatches(folderId: folderId)
        isEmpty = local.isEmpty
        isLoading = false
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
            await spawn(c)
        }
        if !byId.isEmpty { isEmpty = false }
    }

    func add(_ c: CloudCatch) async {
        byId[c.id] = c
        isEmpty = false
        await spawn(c)
    }

    private func spawn(_ c: CloudCatch) async {
        guard let display = await repo.displayImage(for: c) else { return }
        let body = await repo.bodyImage(for: c) ?? display
        scene.addCatch(id: c.id, display: display, body: body)
    }

    private func remove(_ id: UUID) async {
        guard let c = byId[id] else { return }
        byId[id] = nil
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
            Menu {
                Button { showFolders = true } label: { Label("폴더 관리", systemImage: "folder") }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .liquidGlass(Circle(), interactive: true)
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
