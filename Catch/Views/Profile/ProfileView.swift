import SwiftUI

/// 타 유저(또는 본인) 프로필 — 수집 항아리 + 카운트 + 팔로우.
struct ProfileView: View {
    let userId: UUID
    var isSelf: Bool = false

    @State private var profile: Profile?
    @State private var counts: ProfileCounts?
    @State private var following = false
    @State private var working = false
    private let repo = ProfileRepository.shared

    var body: some View {
        ZStack(alignment: .top) {
            JarView { try await CatchRepository.shared.loadUser(userId) }

            header
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMeta() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(profile?.displayName ?? " ")
                .font(.headline).foregroundStyle(.white)
            Text("@\(profile?.username ?? "")")
                .font(.subheadline).foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 28) {
                stat("수집", counts?.collections)
                stat("팔로워", counts?.followers)
                stat("팔로잉", counts?.following)
            }

            if !isSelf {
                Button {
                    Task { await toggleFollow() }
                } label: {
                    Text(following ? "팔로잉" : "팔로우")
                        .font(.subheadline.bold())
                        .foregroundStyle(following ? .white : .black)
                        .frame(width: 120, height: 36)
                        .background(following ? Color.white.opacity(0.15) : Color.white,
                                    in: Capsule())
                }
                .disabled(working)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 2) {
            Text(value.map(String.init) ?? "—")
                .font(.headline).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func loadMeta() async {
        profile = await repo.profile(id: userId)
        counts = await repo.counts(userId)
        if !isSelf { following = await repo.isFollowing(userId) }
    }

    private func toggleFollow() async {
        working = true
        if following {
            await repo.unfollow(userId); following = false
        } else {
            await repo.follow(userId); following = true
        }
        counts = await repo.counts(userId)
        working = false
    }
}
