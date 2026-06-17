import Foundation

/// 수집 정리용 폴더 (public.folders)
struct Folder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var isPublic: Bool
    var sort: Int

    enum CodingKeys: String, CodingKey {
        case id, name, sort
        case isPublic = "is_public"
    }
}
