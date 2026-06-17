import Foundation
import Supabase

/// 피드 행(소유자 정보 + 좋아요 여부 포함)
struct FeedRow: Codable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    let imagePath: String
    let bodyPath: String?
    let likeCount: Int
    let caughtAt: String      // ISO, 키셋 커서
    let username: String?
    let displayName: String?
    let liked: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, liked
        case ownerId = "owner_id"
        case imagePath = "image_path"
        case bodyPath = "body_path"
        case likeCount = "like_count"
        case caughtAt = "caught_at"
        case displayName = "display_name"
    }
}

@MainActor
final class FeedRepository {
    static let shared = FeedRepository()

    struct CursorParams: Encodable {
        let p_limit: Int
        let p_before: String?
        let p_before_id: String?
    }

    /// 다음 페이지. `after`가 nil이면 첫 페이지.
    func page(after last: FeedRow?, limit: Int = 20) async -> [FeedRow] {
        let params = CursorParams(p_limit: limit,
                                  p_before: last?.caughtAt,
                                  p_before_id: last?.id.uuidString)
        return (try? await Supa.client.rpc("following_feed_rich", params: params).execute().value) ?? []
    }

    func like(_ catchId: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("likes")
            .insert(["user_id": me.uuidString, "catch_id": catchId.uuidString]).execute()
    }

    func unlike(_ catchId: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("likes").delete()
            .eq("user_id", value: me.uuidString)
            .eq("catch_id", value: catchId.uuidString).execute()
    }
}
