import Foundation

/// 수집 정리용 폴더 (public.folders)
struct Folder: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var isPublic: Bool
    var sort: Int
    var shape: Int?      // 모양 인덱스(null = id 기반 기본)
    var color: Int?      // 색 팔레트 인덱스(null = 라임)

    enum CodingKeys: String, CodingKey {
        case id, name, sort, shape, color
        case isPublic = "is_public"
    }
}
