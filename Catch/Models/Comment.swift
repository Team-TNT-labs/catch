import Foundation

/// 댓글 (rpc comments_for: 작성자 정보 포함)
struct Comment: Codable, Identifiable, Equatable {
    let id: UUID
    let authorId: UUID
    let body: String
    let createdAt: String
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, body, username
        case authorId = "author_id"
        case createdAt = "created_at"
        case displayName = "display_name"
    }
}
