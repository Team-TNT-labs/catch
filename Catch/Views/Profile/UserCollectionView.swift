import SwiftUI
import SpriteKit

/// 타 유저 수집(스티커+폴더) 읽기전용 물리 잼.
@MainActor
final class UserJarHolder: ObservableObject {
    let scene = StickerScene(size: CGSize(width: 390, height: 844))
    @Published var isLoading = true
    @Published var isEmpty = false
    @Published var currentFolder: Folder?
    @Published var focused: CloudCatch?
    @Published var focusedImage: UIImage?

    private let userId: UUID
    private var folders: [Folder] = []
    private var allCatches: [CloudCatch] = []
    private var byId: [UUID: CloudCatch] = [:]
    private let repo = CatchRepository.shared
    private var loaded = false

    init(userId: UUID) {
        self.userId = userId
        scene.scaleMode = .resizeFill
        scene.readOnly = true
        scene.onTapCatch = { [weak self] id in Task { await self?.focus(id) } }
        scene.onOpenFolder = { [weak self] id in Task { await self?.enterFolder(id) } }
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        folders = await FolderRepository.shared.listUser(userId)
        allCatches = ((try? await repo.loadUser(userId)) ?? [])
        isLoading = false
        await reload(folderId: nil)
    }

    func enterFolder(_ id: UUID) async {
        currentFolder = folders.first { $0.id == id }
        await reload(folderId: id)
    }

    func exitToRoot() async {
        currentFolder = nil
        await reload(folderId: nil)
    }

    private func reload(folderId: UUID?) async {
        scene.clearAll(); byId.removeAll()
        // 루트면 공개 폴더들을 모양 노드로 먼저 투하.
        if folderId == nil {
            for f in folders {
                scene.addFolder(id: f.id, name: f.name, shape: f.shape, color: f.color, labelColor: f.labelColor)
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
        for c in allCatches where c.folderId == folderId {
            byId[c.id] = c
            try? await Task.sleep(nanoseconds: 60_000_000)
            await spawn(c)
        }
        isEmpty = folders.isEmpty && allCatches.isEmpty
    }

    private func spawn(_ c: CloudCatch) async {
        guard let body = await repo.bodyImage(for: c) else { return }
        let prepared = await Task.detached(priority: .userInitiated) { body.whiteStickerBordered() }.value
        scene.addCatch(id: c.id, bordered: prepared.bordered, working: prepared.working, body: body)
    }

    func focus(_ id: UUID) async {
        guard let c = byId[id], let img = await repo.displayImage(for: c) else { return }
        focusedImage = img.whiteStickerBordered().bordered
        focused = c
    }

    func dismissFocus() { focused = nil; focusedImage = nil }
}

struct UserCollectionView: View {
    let userId: UUID
    @StateObject private var holder: UserJarHolder

    init(userId: UUID) {
        self.userId = userId
        _holder = StateObject(wrappedValue: UserJarHolder(userId: userId))
    }

    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: holder.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea(edges: .bottom)

            if holder.isLoading {
                CatchLoader().padding(.top, 80)
            } else if holder.isEmpty {
                Text("아직 수집이 없어요 🫧")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink.opacity(0.5)).padding(.top, 80)
            }

            // 폴더 안: 상단에 폴더명 + 뒤로가기.
            if let folder = holder.currentFolder {
                HStack(spacing: 10) {
                    Button { Task { await holder.exitToRoot() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white).frame(width: 38, height: 38)
                            .liquidGlass(Circle(), interactive: true)
                    }
                    Text(folder.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            holder.scene.toolbarBarrier = (width: 226, height: 72, bottomMargin: deviceSafeAreaBottom + 6)
            await holder.loadIfNeeded()
        }
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
    }
}
