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

/// 프로필 탭 — 인스타식 헤더(아바타+닉네임+카운트) + 팔로잉 서클(중력/그리드).
struct ProfilePageView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var follow = FollowHolder()

    @State private var counts: ProfileCounts?
    @State private var navTarget: UUID?
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var photoItem: PhotosPickerItem?

    private var hasAvatar: Bool { !(auth.profile?.avatarUrl ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                followSection
            }
            .padding(.top, 8)
            .background(Color.black.ignoresSafeArea())
            .navigationDestination(item: $navTarget) { ProfileView(userId: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
        }
        .task {
            if let id = auth.profile?.id { counts = await ProfileRepository.shared.counts(id) }
            await follow.loadIfNeeded()
        }
        .onChange(of: follow.tapped) { _, id in if let id { navTarget = id; follow.tapped = nil } }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(auth) }
        .sheet(isPresented: $showSearch) { UserSearchView() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(path: auth.profile?.avatarUrl, fallbackText: auth.profile?.username, size: 96)
                        .overlay(Circle().strokeBorder(Theme.lime, lineWidth: 2))
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 28, height: 28).background(Theme.lime, in: Circle())
                        .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                }
            }

            Text(auth.profile?.username ?? "이름 없음")
                .font(.title3.bold()).foregroundStyle(Theme.ink)

            HStack(spacing: 0) {
                stat("collected", counts?.collections)
                stat("followers", counts?.followers)
                stat("following", counts?.following)
            }
            .padding(.top, 2)

            if hasAvatar {
                Button("사진 삭제", role: .destructive) {
                    Task { await ProfileRepository.shared.removeAvatar(); auth.setAvatarPath(nil) }
                }
                .font(.caption).tint(Theme.muted)
            }
        }
        .padding(.horizontal, 24)
        .onChange(of: photoItem) { _, item in Task { await applyPicked(item) } }
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 3) {
            Text(value.map(String.init) ?? "—").font(.title3.bold()).foregroundStyle(Theme.ink)
            Text(label).font(.mono(10)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Following circles

    private var followSection: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: follow.scene, options: [.allowsTransparency, .ignoresSiblingOrder])
                .background(Color.clear)

            if follow.isEmpty {
                emptyFollow.padding(.top, 60)
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
            .padding(.horizontal, 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var emptyFollow: some View {
        VStack(spacing: 8) {
            Text("아직 팔로우한 친구가 없어요").font(.subheadline).foregroundStyle(Theme.muted)
            Button { showSearch = true } label: {
                Label("친구 찾기", systemImage: "magnifyingglass")
                    .font(.subheadline.bold()).foregroundStyle(.black)
                    .padding(.horizontal, 18).frame(height: 42).background(Theme.coral, in: Capsule())
            }
        }
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
