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

    private struct CountRow: Decodable { let comment_count: Int }

    private var cache: [UUID: [Comment]] = [:]   // 메모리 캐시

    /// 캐시된 댓글(있으면 즉시 표시용).
    func cached(_ catchId: UUID) -> [Comment]? { cache[catchId] }

    func list(_ catchId: UUID) async -> [Comment] {
        let rows: [Comment] = (try? await Supa.client
            .rpc("comments_for", params: ["p_catch": catchId.uuidString])
            .execute().value) ?? []
        cache[catchId] = rows
        return rows
    }

    /// 댓글 수(catches.comment_count 트리거 값).
    func count(_ catchId: UUID) async -> Int {
        let rows: [CountRow] = (try? await Supa.client
            .from("catches").select("comment_count")
            .eq("id", value: catchId.uuidString).execute().value) ?? []
        return rows.first?.comment_count ?? 0
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
