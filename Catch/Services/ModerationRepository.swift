import Foundation
import Supabase

/// 신고·차단 (App Store UGC 정책: 공개 콘텐츠엔 신고·차단 필수)
@MainActor
final class ModerationRepository {
    static let shared = ModerationRepository()

    func report(catchId: UUID? = nil, userId: UUID? = nil, reason: String) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        let type = catchId != nil ? "catch" : "user"
        guard let targetId = (catchId ?? userId)?.uuidString else { return }
        _ = try? await Supa.client.from("reports").insert([
            "reporter_id": me.uuidString,
            "target_type": type,
            "target_id": targetId,
            "reason": reason
        ]).execute()
    }

    func block(_ userId: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("blocks").insert([
            "blocker_id": me.uuidString,
            "blocked_id": userId.uuidString
        ]).execute()
    }

    func unblock(_ userId: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("blocks").delete()
            .eq("blocker_id", value: me.uuidString)
            .eq("blocked_id", value: userId.uuidString).execute()
    }
}
