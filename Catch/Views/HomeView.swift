import SwiftUI
import SpriteKit

/// 물리 씬 + 클라우드 수집 로딩/삭제를 담당한다.
@MainActor
final class SceneHolder: ObservableObject {
    let scene: StickerScene
    private let repo = CatchRepository.shared

    @Published var isLoading = true
    @Published var isEmpty = false

    private var byId: [UUID: CloudCatch] = [:]
    private var loadedOnce = false

    init() {
        let scene = StickerScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        self.scene = scene
        scene.onDeleteCatch = { [weak self] id in
            Task { await self?.remove(id) }
        }
    }

    func loadMineIfNeeded() async {
        guard !loadedOnce else { return }
        loadedOnce = true
        await reload(folderId: nil)
    }

    /// 폴더 필터로 항아리를 다시 채운다(nil = 전체).
    func reload(folderId: UUID?) async {
        isLoading = true
        scene.clearAll()
        byId.removeAll()
        let catches = (try? await repo.loadMine(folderId: folderId)) ?? []
        isEmpty = catches.isEmpty
        isLoading = false
        for c in catches {
            byId[c.id] = c
            try? await Task.sleep(nanoseconds: 80_000_000)
            await spawn(c, isNew: false)
        }
    }

    func add(_ c: CloudCatch) async {
        byId[c.id] = c
        isEmpty = false
        await spawn(c, isNew: true)
    }

    private func spawn(_ c: CloudCatch, isNew: Bool) async {
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

/// 홈 = 내 수집(물리 항아리). 우측 하단 버튼으로 카메라.
struct HomeView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var holder = SceneHolder()
    @State private var showCamera = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var counts: ProfileCounts?
    @State private var folders: [Folder] = []
    @State private var selectedFolder: UUID?
    @State private var showFolders = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SpriteView(scene: holder.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea()

            if holder.isLoading {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if holder.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.fingers.spread")
                        .font(.system(size: 40)).foregroundStyle(.white.opacity(0.5))
                    Text("무언가를 찍어 스티커로 모아보세요")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            // 좌측 상단 프로필/설정
            VStack {
                HStack {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(12)
                    }
                    Spacer()
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(14)
                    }
                }
                if let c = counts {
                    HStack(spacing: 24) {
                        countItem("수집", c.collections)
                        countItem("팔로워", c.followers)
                        countItem("팔로잉", c.following)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 18)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                }

                folderBar
                    .padding(.top, 6)

                Spacer()
            }

            // 우측 하단 카메라
            Button { showCamera = true } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 8)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 40)
        }
        .task { await holder.loadMineIfNeeded() }
        .task {
            if let id = auth.profile?.id { counts = await ProfileRepository.shared.counts(id) }
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraFlowView(
                onCatch: { cloud in Task { await holder.add(cloud) } },
                onClose: { showCamera = false }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(auth)
        }
        .sheet(isPresented: $showSearch) {
            UserSearchView()
        }
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("전체", selected: selectedFolder == nil) {
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
                        .font(.footnote.bold())
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(.white.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .bold : .regular))
                .foregroundStyle(selected ? .black : .white.opacity(0.85))
                .padding(.horizontal, 14).frame(height: 30)
                .background(selected ? Color.white : Color.white.opacity(0.1), in: Capsule())
        }
    }

    private func countItem(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(.subheadline.bold()).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
    }
}
