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

    func loadIfNeeded(of userId: UUID) async {
        guard !loaded else { return }
        loaded = true
        let people = await ProfileRepository.shared.following(of: userId)
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
/// 고정 헤더(아바타 + 아이디 + 수집/팔로워/팔로잉) + 그 아래 팔로잉 서클 중력 물리.
struct ProfilePageView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var follow = FollowHolder()

    @State private var counts: ProfileCounts?
    @State private var collectCount = 0
    @State private var navTarget: UUID?
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?

    private var hasAvatar: Bool { !(auth.profile?.avatarUrl ?? "").isEmpty }
    private var username: String { auth.profile?.username ?? "이름 없음" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                followingSection
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)   // large-title 영역 제거 → 헤더 위로 붙음
            .navigationDestination(item: $navTarget) { ProfileView(userId: $0) }
            .navigationDestination(for: FollowListRoute.self) { FollowListView(userId: $0.userId, kind: $0.kind) }
            .navigationDestination(for: UUID.self) { ProfileView(userId: $0) }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(username).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { follow.toggleGrid() } label: {
                        Image(systemName: follow.gridMode ? "circle.grid.3x3.fill" : "square.grid.2x2")
                            .foregroundStyle(.white)
                    }
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.white)
                    }
                }
            }
        }
        .task {
            // 항아리와 동일하게 하단 떠있는 탭바 충돌 배리어 설정 — 서클이 바에 안 가려지게.
            follow.scene.toolbarBarrier = (width: 226, height: 72, bottomMargin: deviceSafeAreaBottom + 6)
            collectCount = CatchRepository.shared.localCatches().count
            if let id = auth.profile?.id {
                counts = await ProfileRepository.shared.counts(id)
                await follow.loadIfNeeded(of: id)
            }
            collectCount = (await CatchRepository.shared.loadMine()).count
        }
        .onChange(of: follow.tapped) { _, id in if let id { navTarget = id; follow.tapped = nil } }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(auth) }
        .sheet(isPresented: $showSearch) { UserSearchView() }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in Task { await applyPicked(item) } }
    }

    // MARK: - Header (avatar-left + horizontal stats)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 22) {
                Menu {
                    Button { showPicker = true } label: { Label("사진 변경", systemImage: "photo") }
                    if hasAvatar {
                        Button(role: .destructive) {
                            Task { await ProfileRepository.shared.removeAvatar(); auth.setAvatarPath(nil) }
                        } label: { Label("사진 삭제", systemImage: "trash") }
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(path: auth.profile?.avatarUrl, fallbackText: username, size: 88)
                            .overlay(Circle().strokeBorder(Theme.lime, lineWidth: 2.5))
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .black)).foregroundStyle(.black)
                            .frame(width: 26, height: 26).background(Theme.lime, in: Circle())
                            .overlay(Circle().strokeBorder(.black, lineWidth: 2.5))
                    }
                }

                HStack(spacing: 0) {
                    statContent("수집", collectCount)
                    statLink("팔로워", counts?.followers, .followers)
                    statLink("팔로잉", counts?.following, .following)
                }
            }

            // 소개(이름은 상단 중앙 툴바로)
            if let bio = auth.profile?.bio, !bio.isEmpty {
                Text(bio).font(.system(size: 13)).foregroundStyle(Theme.ink.opacity(0.85))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func statContent(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 3) {
            Text(value.map(String.init) ?? "—").font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    /// 팔로워/팔로잉 — 탭하면 해당 리스트로 이동(내 id 있을 때만).
    @ViewBuilder private func statLink(_ label: String, _ value: Int?, _ kind: FollowKind) -> some View {
        if let uid = auth.profile?.id {
            NavigationLink(value: FollowListRoute(userId: uid, kind: kind)) {
                statContent(label, value)
            }
            .buttonStyle(.plain)
        } else {
            statContent(label, value)
        }
    }

    // MARK: - Following circles (gravity)

    private var followingSection: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: follow.scene, options: [.allowsTransparency, .ignoresSiblingOrder])
                .background(Color.clear)
                .ignoresSafeArea(edges: .bottom)   // 씬 바닥=화면 바닥 → 하단 탭바 배리어 좌표 일치

            if follow.isEmpty {
                emptyState("아직 팔로우한 친구가 없어요", action: { showSearch = true }).padding(.top, 70)
            }
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
