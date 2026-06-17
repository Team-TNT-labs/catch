import Foundation
import Supabase

private struct FollowRow: Decodable { let follower_id: UUID }

/// 프로필 검색·카운트·팔로우.
@MainActor
final class ProfileRepository {
    static let shared = ProfileRepository()

    func search(_ query: String) async -> [Profile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let me = try? await Supa.client.auth.session.user.id
        let results: [Profile] = (try? await Supa.client
            .from("profiles").select()
            .ilike("username", pattern: "%\(q)%")
            .limit(20)
            .execute().value) ?? []
        return results.filter { $0.id != me }   // 본인 제외
    }

    func profile(id: UUID) async -> Profile? {
        try? await Supa.client.from("profiles").select().eq("id", value: id.uuidString)
            .single().execute().value
    }

    func counts(_ userId: UUID) async -> ProfileCounts? {
        let rows: [ProfileCounts]? = try? await Supa.client
            .rpc("profile_counts", params: ["p_user": userId.uuidString])
            .execute().value
        return rows?.first
    }

    func isFollowing(_ target: UUID) async -> Bool {
        guard let me = try? await Supa.client.auth.session.user.id else { return false }
        let rows: [FollowRow] = (try? await Supa.client
            .from("follows").select("follower_id")
            .eq("follower_id", value: me.uuidString)
            .eq("followee_id", value: target.uuidString)
            .execute().value) ?? []
        return !rows.isEmpty
    }

    func follow(_ target: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("follows")
            .insert(["follower_id": me.uuidString, "followee_id": target.uuidString])
            .execute()
    }

    func unfollow(_ target: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("follows").delete()
            .eq("follower_id", value: me.uuidString)
            .eq("followee_id", value: target.uuidString)
            .execute()
    }
}
