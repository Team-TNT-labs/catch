import UIKit
import Supabase

enum CatchError: Error { case encodingFailed, notAuthed }

/// 캐치 업로드/조회/삭제. 이미지는 Supabase Storage, 메타는 catches 테이블.
/// 다운로드한 이미지는 로컬 Caches에 캐싱한다.
@MainActor
final class CatchRepository {
    static let shared = CatchRepository()

    private let bucket = "stickers"
    private let fm = FileManager.default

    private var cacheDir: URL {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catchimages", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private func cacheURL(_ path: String) -> URL {
        cacheDir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    // MARK: - Upload
    func upload(image: UIImage) async throws -> CloudCatch {
        let uid = try await Supa.client.auth.session.user.id
        let id = UUID()
        // 방향 정규화(EXIF/GPS 베이크 제거) → 1024 상한 → 투명 여백 트림
        let normalized = image.orientationNormalized()
            .resized(maxDimension: 1024)
            .trimmingTransparentPixels()
        let body = normalized.resized(maxDimension: 256)
        guard let png = normalized.pngData(), let bodyPng = body.pngData() else {
            throw CatchError.encodingFailed
        }
        let imagePath = "catches/\(uid.uuidString)/\(id.uuidString).png"
        let bodyPath = "catches/\(uid.uuidString)/\(id.uuidString)_body.png"

        let opts = FileOptions(contentType: "image/png", upsert: true)
        try await Supa.client.storage.from(bucket).upload(imagePath, data: png, options: opts)
        try await Supa.client.storage.from(bucket).upload(bodyPath, data: bodyPng, options: opts)

        let payload = CatchInsert(
            id: id.uuidString, owner_id: uid.uuidString,
            image_path: imagePath, body_path: bodyPath,
            width: Int(normalized.size.width), height: Int(normalized.size.height)
        )
        let inserted: CloudCatch = try await Supa.client
            .from("catches").insert(payload).select().single().execute().value

        // 로컬 캐시
        try? png.write(to: cacheURL(imagePath))
        try? bodyPng.write(to: cacheURL(bodyPath))
        return inserted
    }

    // MARK: - Load
    func loadMine() async throws -> [CloudCatch] {
        let uid = try await Supa.client.auth.session.user.id
        return try await Supa.client
            .from("catches").select()
            .eq("owner_id", value: uid.uuidString)
            .order("caught_at", ascending: true)
            .execute().value
    }

    // MARK: - Images (캐시 우선, 없으면 다운로드)
    func image(at path: String) async -> UIImage? {
        let url = cacheURL(path)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return img }
        do {
            let data = try await Supa.client.storage.from(bucket).download(path: path)
            try? data.write(to: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    func displayImage(for c: CloudCatch) async -> UIImage? { await image(at: c.imagePath) }
    func bodyImage(for c: CloudCatch) async -> UIImage? {
        if let bp = c.bodyPath, let img = await image(at: bp) { return img }
        return await displayImage(for: c)
    }

    // MARK: - Delete
    func delete(_ c: CloudCatch) async {
        try? await Supa.client.from("catches").delete().eq("id", value: c.id.uuidString).execute()
        var paths = [c.imagePath]
        if let bp = c.bodyPath { paths.append(bp) }
        _ = try? await Supa.client.storage.from(bucket).remove(paths: paths)
        for p in paths { try? fm.removeItem(at: cacheURL(p)) }
    }
}
