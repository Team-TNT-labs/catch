import Foundation

/// 저장된 스티커 한 개의 메타데이터.
struct Sticker: Codable, Identifiable, Equatable {
    let id: UUID
    let filename: String      // "<uuid>.png" — 표시용(방향 정규화 원본)
    let bodyFilename: String  // "<uuid>_body.png" — 물리 바디용 다운스케일 캐시
    let createdAt: Date
}
