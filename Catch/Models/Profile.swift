import Foundation

/// 사용자 프로필 (public.profiles)
struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var username: String?
    var displayName: String?
    var avatarUrl: String?
    var bio: String?

    enum CodingKeys: String, CodingKey {
        case id, username, bio
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }

    var hasUsername: Bool { !(username ?? "").isEmpty }
}

/// 프로필 카운트 (rpc profile_counts)
struct ProfileCounts: Codable, Equatable {
    let collections: Int
    let followers: Int
    let following: Int
}
