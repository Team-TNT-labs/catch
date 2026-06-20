import SwiftUI

/// 팔로워/팔로잉 라우트 — NavigationLink(value:)로 전달.
struct FollowListRoute: Hashable {
    let userId: UUID
    let kind: FollowKind
}

enum FollowKind: Hashable {
    case followers, following
    var title: String { self == .followers ? "팔로워" : "팔로잉" }
}

/// 팔로워/팔로잉 사용자 리스트 — 탭하면 해당 프로필로 이동.
struct FollowListView: View {
    let userId: UUID
    let kind: FollowKind

    @State private var people: [Profile] = []
    @State private var loading = true

    var body: some View {
        List(people) { p in
            NavigationLink(value: p.id) { row(p) }
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Theme.muted.opacity(0.2))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if loading {
                CatchLoader()
            } else if people.isEmpty {
                ContentUnavailableView(
                    kind == .followers ? "아직 팔로워가 없어요" : "아직 팔로우한 친구가 없어요",
                    systemImage: "person.2"
                )
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            people = kind == .followers
                ? await ProfileRepository.shared.followers(of: userId)
                : await ProfileRepository.shared.following(of: userId)
            loading = false
        }
    }

    private func row(_ p: Profile) -> some View {
        HStack(spacing: 12) {
            AvatarView(path: p.avatarUrl, fallbackText: p.username, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.username ?? "Catch 사용자")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                if let dn = p.displayName, !dn.isEmpty, dn != p.username {
                    Text(dn).font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
