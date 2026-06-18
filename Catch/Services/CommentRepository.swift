import Foundation
import Supabase

/// 댓글 조회/작성/삭제. 가시성·권한은 RLS가 강제.
@MainActor
final class CommentRepository {
    static let shared = CommentRepository()

    private struct Insert: Encodable {
        let catch_id: String
        let author_id: String
        let body: String
    }

    func list(_ catchId: UUID) async -> [Comment] {
        (try? await Supa.client
            .rpc("comments_for", params: ["p_catch": catchId.uuidString])
            .execute().value) ?? []
    }

    @discardableResult
    func add(_ catchId: UUID, body: String) async -> Bool {
        guard let me = try? await Supa.client.auth.session.user.id else { return false }
        let payload = Insert(catch_id: catchId.uuidString.lowercased(),
                             author_id: me.uuidString.lowercased(),
                             body: body)
        do {
            try await Supa.client.from("comments").insert(payload).execute()
            return true
        } catch {
            Log.data.error("comment insert failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func delete(_ id: UUID) async {
        _ = try? await Supa.client.from("comments").delete().eq("id", value: id.uuidString).execute()
    }
}
