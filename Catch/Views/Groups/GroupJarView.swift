import SwiftUI
import SpriteKit

/// 그룹 공유 항아리 보유자 — 멤버들이 담은 스티커가 한 항아리에 쌓임(읽기전용 물리).
@MainActor
final class GroupJarHolder: ObservableObject {
    let scene = StickerScene(size: CGSize(width: 390, height: 844))
    @Published var isLoading = true
    @Published var isEmpty = false
    @Published var isGrid = false
    @Published var members: [GroupMember] = []
    @Published var focused: CloudCatch?
    @Published var focusedImage: UIImage?

    let group: CatchGroup
    private(set) var cat: [CloudCatch] = []
    private var byId: [UUID: CloudCatch] = [:]
    private let repo = CatchRepository.shared
    private var loaded = false

    init(group: CatchGroup) {
        self.group = group
        scene.scaleMode = .resizeFill
        scene.readOnly = true
        scene.plainBackground = true
        scene.onTapCatch = { [weak self] id in Task { await self?.focus(id) } }
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        members = await GroupRepository.shared.members(group.id)
        cat = await GroupRepository.shared.catches(group.id)
        isEmpty = cat.isEmpty
        isLoading = false
        for c in cat {
            byId[c.id] = c
            try? await Task.sleep(nanoseconds: 55_000_000)
            await spawn(c)
        }
    }

    func reload() async {
        loaded = false; scene.clearAll(); byId.removeAll(); isLoading = true; isGrid = false; scene.isPaused = false
        await loadIfNeeded()
    }

    func toggleGrid() { isGrid.toggle(); scene.isPaused = isGrid }

    private func spawn(_ c: CloudCatch) async {
        guard let body = await repo.bodyImage(for: c) else { return }
        let prepared = await Task.detached(priority: .userInitiated) { body.whiteStickerBordered() }.value
        scene.addCatch(id: c.id, bordered: prepared.bordered, working: prepared.working, body: body)
    }

    func focus(_ id: UUID) async {
        guard let c = byId[id] ?? cat.first(where: { $0.id == id }),
              let img = await repo.displayImage(for: c) else { return }
        let bordered = await Task.detached(priority: .userInitiated) { img.whiteStickerBordered().bordered }.value
        focusedImage = bordered
        scene.isPaused = true
        focused = c
    }

    func dismissFocus() {
        focused = nil; focusedImage = nil
        if !isGrid { scene.isPaused = false }
    }
}

struct GroupJarView: View {
    let group: CatchGroup
    @StateObject private var holder: GroupJarHolder
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false

    private var isOwner: Bool { Supa.client.auth.currentSession?.user.id == group.ownerId }

    init(group: CatchGroup) {
        self.group = group
        _holder = StateObject(wrappedValue: GroupJarHolder(group: group))
    }

    var body: some View {
        VStack(spacing: 0) {
            memberBar
            jarArea
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if let c = holder.focused {
                StickerDetailView(
                    catchId: c.id, imagePath: c.imagePath, ownerId: c.ownerId,
                    initialTitle: c.title, preloaded: holder.focusedImage,
                    onClose: { holder.dismissFocus() }
                )
                .ignoresSafeArea()
                .transition(.scale(scale: 0.9, anchor: .center).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: holder.focused != nil)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(group.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { holder.toggleGrid() } label: {
                    Image(systemName: holder.isGrid ? "circle.grid.3x3.fill" : "square.grid.2x2").foregroundStyle(.white)
                }
            }
            if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .topBarTrailing) }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: "Catch 그룹 '\(group.name)' 초대코드: \(group.inviteCode)") {
                        Label("초대코드 공유", systemImage: "square.and.arrow.up")
                    }
                    if isOwner {
                        Button { showEdit = true } label: { Label("그룹 편집", systemImage: "pencil").foregroundStyle(.white) }
                        Button { Task { await GroupRepository.shared.delete(group.id); dismiss() } } label: {
                            Label("그룹 삭제", systemImage: "trash").foregroundStyle(.white)
                        }
                    } else {
                        Button { Task { await GroupRepository.shared.leave(group.id); dismiss() } } label: {
                            Label("그룹 나가기", systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(.white)
                        }
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.white) }
            }
        }
        .task {
            holder.scene.toolbarBarrier = (width: SetlogBottomBar.pillWidth, height: SetlogBottomBar.pillHeight, bottomMargin: deviceSafeAreaBottom + 6)
            await holder.loadIfNeeded()
        }
        .sheet(isPresented: $showEdit) { GroupEditView(existing: group) { await holder.reload() } }
    }

    // MARK: - 멤버 + 초대코드 바

    private var memberBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach(holder.members.prefix(6)) { m in
                    AvatarView(path: m.profile?.avatarUrl, fallbackText: m.profile?.username, size: 34)
                        .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                }
            }
            if holder.members.count > 6 {
                Text("+\(holder.members.count - 6)").font(.caption.bold()).foregroundStyle(Theme.muted)
            }
            Spacer()
            ShareLink(item: "Catch 그룹 '\(group.name)' 초대코드: \(group.inviteCode)") {
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.plus").font(.system(size: 13, weight: .bold))
                    Text(group.inviteCode).font(.system(size: 13, weight: .heavy)).monospaced()
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Theme.lime, in: Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    // MARK: - 항아리

    private var jarArea: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: holder.scene, options: [.ignoresSiblingOrder])
                .ignoresSafeArea(edges: .bottom)

            if holder.isGrid { grid.transition(.opacity) }

            if holder.isLoading {
                CatchLoader().padding(.top, 80)
            } else if holder.isEmpty {
                VStack(spacing: 8) {
                    Text("아직 담긴 스티커가 없어요 🫧").font(.subheadline).foregroundStyle(Theme.muted)
                    Text("스티커를 눌러 '그룹에 담기' 해보세요").font(.caption).foregroundStyle(Theme.muted.opacity(0.7))
                }
                .padding(.top, 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: holder.isGrid)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 14) {
                ForEach(holder.cat) { c in
                    Button { Task { await holder.focus(c.id) } } label: {
                        BorderedStickerImage(path: c.bodyPath ?? c.imagePath)
                            .padding(10).frame(height: 116).frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16)
            .padding(.bottom, deviceSafeAreaBottom + 96)
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
    }
}
