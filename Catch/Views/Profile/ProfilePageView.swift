import SwiftUI
import SpriteKit
import PhotosUI

/// 팔로잉 서클 물리 씬 보유자.
@MainActor
final class FollowHolder: ObservableObject {
    let scene = FollowScene(size: CGSize(width: 390, height: 600))
    @Published var gridMode = false
    @Published var isEmpty = false
    @Published var tapped: UUID?
    private var loaded = false

    init() {
        scene.scaleMode = .resizeFill
        scene.onTapPerson = { [weak self] id in self?.tapped = id }
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        let people = await ProfileRepository.shared.following()
        isEmpty = people.isEmpty
        for p in people {
            var avatar: UIImage?
            if let path = p.avatarUrl, !path.isEmpty {
                avatar = await ProfileRepository.shared.avatarImage(path: path)
            }
            let circle = personCircleImage(avatar: avatar, initial: p.username ?? "?")
            try? await Task.sleep(nanoseconds: 60_000_000)
            scene.addPerson(id: p.id, image: circle)
        }
    }

    func toggleGrid() {
        gridMode.toggle()
        if gridMode { scene.arrangeGrid() } else { scene.releaseGrid() }
    }
}

/// 프로필 탭 — 인스타그램식 레이아웃.
/// 상단 헤더(아바타-좌측 + 가로 스탯 + 이름/소개 + 편집 버튼) → 탭 스트립 → 콘텐츠(수집 그리드 / 팔로잉).
struct ProfilePageView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var follow = FollowHolder()

    @State private var counts: ProfileCounts?
    @State private var myCatches: [CloudCatch] = []
    @State private var tab: ProfileTab = .grid
    @State private var navTarget: UUID?
    @State private var detailCatch: CloudCatch?
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var photoItem: PhotosPickerItem?

    enum ProfileTab { case grid, following }

    private var hasAvatar: Bool { !(auth.profile?.avatarUrl ?? "").isEmpty }
    private var username: String { auth.profile?.username ?? "이름 없음" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                buttonsRow
                tabStrip
                content
            }
            .background(Color.black.ignoresSafeArea())
            .navigationDestination(item: $navTarget) { ProfileView(userId: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        Text(username).font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showSearch = true } label: {
                            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold))
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "line.3.horizontal").font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        }
        .task {
            myCatches = CatchRepository.shared.localCatches()
            if let id = auth.profile?.id { counts = await ProfileRepository.shared.counts(id) }
            await follow.loadIfNeeded()
            myCatches = await CatchRepository.shared.loadMine()
        }
        .onChange(of: follow.tapped) { _, id in if let id { navTarget = id; follow.tapped = nil } }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(auth) }
        .sheet(isPresented: $showSearch) { UserSearchView() }
        .sheet(item: $detailCatch) { c in
            StickerDetailView(
                catchId: c.id, imagePath: c.imagePath, ownerId: c.ownerId,
                initialTitle: c.title, onClose: { detailCatch = nil }
            )
            .presentationBackground(.black)
        }
        .onChange(of: photoItem) { _, item in Task { await applyPicked(item) } }
    }

    // MARK: - Header (avatar-left + horizontal stats)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 22) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(path: auth.profile?.avatarUrl, fallbackText: username, size: 88)
                            .overlay(Circle().strokeBorder(Theme.lime, lineWidth: 2.5))
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .black)).foregroundStyle(.black)
                            .frame(width: 26, height: 26).background(Theme.lime, in: Circle())
                            .overlay(Circle().strokeBorder(.black, lineWidth: 2.5))
                    }
                }

                HStack(spacing: 0) {
                    stat("수집", myCatches.count, counts?.collections)
                    stat("팔로워", nil, counts?.followers)
                    stat("팔로잉", nil, counts?.following)
                }
            }

            // 이름 + 소개
            VStack(alignment: .leading, spacing: 2) {
                Text(username).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                if let bio = auth.profile?.bio, !bio.isEmpty {
                    Text(bio).font(.system(size: 13)).foregroundStyle(Theme.ink.opacity(0.85))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    /// 로컬 수집 수가 있으면 우선(즉시 반영), 없으면 서버 카운트.
    private func stat(_ label: String, _ local: Int?, _ server: Int?) -> some View {
        let value = local ?? server
        return VStack(spacing: 3) {
            Text(value.map(String.init) ?? "—").font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Buttons row (IG식 회색 분할 버튼)

    private var buttonsRow: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                pillLabel("프로필 사진 변경")
            }
            if hasAvatar {
                Button {
                    Task { await ProfileRepository.shared.removeAvatar(); auth.setAvatarPath(nil) }
                } label: { pillLabel("사진 삭제") }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: - Tab strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            tabButton(.grid, "square.grid.3x3")
            tabButton(.following, "person.2")
        }
        .padding(.top, 16)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.muted.opacity(0.25)) }
    }

    private func tabButton(_ t: ProfileTab, _ icon: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { tab = t } } label: {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(tab == t ? Theme.ink : Theme.muted.opacity(0.6))
                .frame(maxWidth: .infinity).frame(height: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(tab == t ? Theme.lime : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch tab {
        case .grid:      collectGrid
        case .following: followingSection
        }
    }

    private var collectGrid: some View {
        Group {
            if myCatches.isEmpty {
                emptyState("아직 수집한 스티커가 없어요 🫧", action: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        ForEach(myCatches) { c in
                            Button { detailCatch = c } label: {
                                BorderedStickerImage(path: c.bodyPath ?? c.imagePath)
                                    .padding(8)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fill)
                                    .background(Theme.surface.opacity(0.4))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, deviceSafeAreaBottom + 90)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var followingSection: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: follow.scene, options: [.allowsTransparency, .ignoresSiblingOrder])
                .background(Color.clear)

            if follow.isEmpty {
                emptyState("아직 팔로우한 친구가 없어요", action: { showSearch = true }).padding(.top, 70)
            }

            HStack {
                Text("following").font(.mono(12)).foregroundStyle(Theme.muted)
                Spacer()
                Button { follow.toggleGrid() } label: {
                    Image(systemName: follow.gridMode ? "circle.grid.3x3.fill" : "square.grid.2x2")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).liquidGlass(Circle(), interactive: true)
                }
            }
            .padding(.horizontal, 18).padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(_ text: String, action: (() -> Void)?) -> some View {
        VStack(spacing: 12) {
            Text(text).font(.subheadline).foregroundStyle(Theme.muted)
            if let action {
                Button(action: action) {
                    Label("친구 찾기", systemImage: "magnifyingglass")
                        .font(.subheadline.bold()).foregroundStyle(.black)
                        .padding(.horizontal, 18).frame(height: 42).background(Theme.coral, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func applyPicked(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        if let path = await ProfileRepository.shared.uploadAvatar(img) {
            auth.setAvatarPath(path)
        }
        photoItem = nil
    }
}
