import Foundation

/// 서버에 저장된 캐치 한 개 (public.catches)
struct CloudCatch: Codable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    var folderId: UUID?
    let imagePath: String
    let bodyPath: String?
    var title: String?
    var isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case id, title
        case ownerId = "owner_id"
        case folderId = "folder_id"
        case imagePath = "image_path"
        case bodyPath = "body_path"
        case isPublic = "is_public"
    }
}

/// 캐치 insert payload
struct CatchInsert: Encodable {
    let id: String
    let owner_id: String
    let image_path: String
    let body_path: String
    let width: Int
    let height: Int
}
