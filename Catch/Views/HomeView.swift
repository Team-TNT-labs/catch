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
            } else if holder.isEmpty {
                VStack(spacing: 8) {
                    Text("🫙").font(.system(size: 52))
                    Text("아래 카메라로 무언가 찍어보세요")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            folderBar
                .padding(.top, 60)
        }
        .task {
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
                Button { showFolders = true } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.footnote.bold()).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(Theme.surface, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
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
