import UIKit
import Supabase

enum CatchError: Error { case encodingFailed, notAuthed }

/// 로컬 매니페스트 엔트리(동기화 여부 포함).
private struct LocalCatch: Codable {
    var cloud: CloudCatch
    var synced: Bool
}

/// 로컬-퍼스트 캐치 저장.
/// 표시는 항상 로컬 매니페스트(mine.json)에서 즉시 — 네트워크를 절대 기다리지 않는다.
/// Supabase 업로드/병합은 백그라운드.
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

    // 로컬 매니페스트(내 모든 캐치)
    private var mineURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("mine.json")
    }
    private func loadLocal() -> [LocalCatch] {
        guard let data = try? Data(contentsOf: mineURL),
              let list = try? JSONDecoder().decode([LocalCatch].self, from: data) else { return [] }
        return list
    }
    private func saveLocal(_ list: [LocalCatch]) {
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: mineURL, options: .atomic) }
    }
    private func markSynced(_ id: UUID) {
        var l = loadLocal()
        if let i = l.firstIndex(where: { $0.cloud.id == id }) { l[i].synced = true; saveLocal(l) }
    }

    /// 즉시(동기) 로컬 캐치 목록 — 항아리 표시용.
    func localCatches(folderId: UUID? = nil) -> [CloudCatch] {
        loadLocal().map { $0.cloud }.filter { folderId == nil || $0.folderId == folderId }
    }

    /// 특정 폴더 소속 캐치만(엄격 일치). nil = 미분류(루트) 캐치.
    func localCatches(inFolder folderId: UUID?) -> [CloudCatch] {
        loadLocal().map { $0.cloud }.filter { $0.folderId == folderId }
    }

    // MARK: - 촬영 직후: 로컬 즉시 저장
    @discardableResult
    func capture(image: UIImage) async throws -> CloudCatch {
        // 로컬-퍼스트: 네트워크 동반 세션 대신 캐시된 로컬 세션 사용(멈춤 방지).
        guard let uid = Supa.client.auth.currentSession?.user.id else { throw CatchError.notAuthed }
        let id = UUID()
        let uidStr = uid.uuidString.lowercased()
        let idStr = id.uuidString.lowercased()
        let imagePath = "catches/\(uidStr)/\(idStr).png"
        let bodyPath = "catches/\(uidStr)/\(idStr)_body.png"

        // 무거운 정규화·트림·PNG 인코딩은 백그라운드에서(메인스레드 블로킹 → 촬영 멈칫 방지).
        let encoded = try await Self.encode(image)
        try? encoded.full.write(to: cacheURL(imagePath))
        try? encoded.body.write(to: cacheURL(bodyPath))

        let cloud = CloudCatch(id: id, ownerId: uid, folderId: nil,
                               imagePath: imagePath, bodyPath: bodyPath, title: nil, isPublic: true)
        var local = loadLocal()
        local.append(LocalCatch(cloud: cloud, synced: false))
        saveLocal(local)
        Task { await self.sync(cloud) }
        return cloud
    }

    /// 표시용/물리 바디용 PNG를 백그라운드에서 인코딩한다.
    private static func encode(_ image: UIImage) async throws -> (full: Data, body: Data) {
        try await Task.detached(priority: .userInitiated) {
            let normalized = image.orientationNormalized().resized(maxDimension: 1024).trimmingTransparentPixels()
            let body = normalized.resized(maxDimension: 256)
            guard let png = normalized.pngData(), let bodyPng = body.pngData() else {
                throw CatchError.encodingFailed
            }
            return (png, bodyPng)
        }.value
    }

    // MARK: - 백그라운드 업로드
    @discardableResult
    private func sync(_ c: CloudCatch) async -> Bool {
        guard let png = try? Data(contentsOf: cacheURL(c.imagePath)) else { return false }
        let opts = FileOptions(contentType: "image/png", upsert: true)
        do {
            try await Supa.client.storage.from(bucket).upload(c.imagePath, data: png, options: opts)
            if let bp = c.bodyPath, let bodyPng = try? Data(contentsOf: cacheURL(bp)) {
                try? await Supa.client.storage.from(bucket).upload(bp, data: bodyPng, options: opts)
            }
            let payload = CatchInsert(id: c.id.uuidString.lowercased(),
                                      owner_id: c.ownerId.uuidString.lowercased(),
                                      image_path: c.imagePath, body_path: c.bodyPath ?? "")
            // 충돌 시 DO NOTHING — 컬럼 제한 UPDATE 권한 불필요(INSERT만).
            try await Supa.client.from("catches").upsert(payload, onConflict: "id", ignoreDuplicates: true).execute()
            markSynced(c.id)
            return true
        } catch {
            // 실패 시 unsynced 유지 → refresh 때 재시도.
            Log.sync.error("catch \(c.id, privacy: .public) upload failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private struct IdRow: Decodable { let id: UUID }
    private var ensuredOnServer: Set<UUID> = []   // 세션 내 서버 존재 확인 캐시

    /// 좋아요/댓글 전에 이 캐치가 서버에 존재하도록 보장(로컬-퍼스트라 미동기화일 수 있음).
    /// 서버 존재를 한 번 확인하면 세션 동안 캐시해 재확인하지 않는다.
    @discardableResult
    func ensureUploaded(_ catchId: UUID) async -> Bool {
        if ensuredOnServer.contains(catchId) { return true }
        guard let entry = loadLocal().first(where: { $0.cloud.id == catchId }) else { return true }
        let rows: [IdRow] = (try? await Supa.client.from("catches")
            .select("id").eq("id", value: catchId.uuidString).execute().value) ?? []
        if !rows.isEmpty { ensuredOnServer.insert(catchId); return true }
        let ok = await sync(entry.cloud)
        if ok { ensuredOnServer.insert(catchId) }
        return ok
    }

    /// 백그라운드: 클라우드와 병합. 새로 받은(다른 기기) 캐치들을 반환. 미동기화분은 재업로드.
    @discardableResult
    func refreshFromCloud() async -> [CloudCatch] {
        guard let uid = try? await Supa.client.auth.session.user.id else { return [] }
        let cloud: [CloudCatch] = (try? await Supa.client
            .from("catches").select().eq("owner_id", value: uid.uuidString)
            .order("caught_at", ascending: true).execute().value) ?? []

        var local = loadLocal()
        let localIds = Set(local.map { $0.cloud.id })
        var added: [CloudCatch] = []
        for c in cloud where !localIds.contains(c.id) {
            local.append(LocalCatch(cloud: c, synced: true))
            added.append(c)
        }
        saveLocal(local)
        for l in local where !l.synced { await sync(l.cloud) }
        return added
    }

    // FoldersView 등에서 쓰는 비동기 래퍼(로컬 즉시 + 백그라운드 refresh)
    func loadMine(folderId: UUID? = nil) async -> [CloudCatch] {
        Task { await refreshFromCloud() }
        return localCatches(folderId: folderId)
    }

    func loadUser(_ userId: UUID) async throws -> [CloudCatch] {
        try await Supa.client.from("catches").select()
            .eq("owner_id", value: userId.uuidString)
            .order("caught_at", ascending: true).execute().value
    }

    // MARK: - Images (로컬 캐시 우선)
    func image(at path: String) async -> UIImage? {
        let url = cacheURL(path)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return img }
        guard let data = try? await Supa.client.storage.from(bucket).download(path: path) else { return nil }
        try? data.write(to: url)
        return UIImage(data: data)
    }
    func displayImage(for c: CloudCatch) async -> UIImage? { await image(at: c.imagePath) }
    func bodyImage(for c: CloudCatch) async -> UIImage? {
        if let bp = c.bodyPath, let img = await image(at: bp) { return img }
        return await displayImage(for: c)
    }

    // MARK: - Delete
    func delete(_ c: CloudCatch) async {
        saveLocal(loadLocal().filter { $0.cloud.id != c.id })
        try? await Supa.client.from("catches").delete().eq("id", value: c.id.uuidString).execute()
        var paths = [c.imagePath]
        if let bp = c.bodyPath { paths.append(bp) }
        _ = try? await Supa.client.storage.from(bucket).remove(paths: paths)
        for p in paths { try? fm.removeItem(at: cacheURL(p)) }
    }

    // MARK: - Caption(title)
    private struct TitleUpdate: Encodable { let title: String? }
    private struct TitleRow: Decodable { let title: String? }

    /// 캡션 저장(로컬 즉시 반영 + 서버). 빈 문자열이면 nil로.
    func setTitle(_ catchId: UUID, _ title: String?) async {
        let value = (title?.isEmpty == true) ? nil : title
        var l = loadLocal()
        if let i = l.firstIndex(where: { $0.cloud.id == catchId }) {
            l[i].cloud.title = value
            saveLocal(l)
        }
        _ = try? await Supa.client.from("catches")
            .update(TitleUpdate(title: value)).eq("id", value: catchId.uuidString).execute()
    }

    /// 서버의 최신 캡션(다른 사용자 캐치 표시용).
    func title(for catchId: UUID) async -> String? {
        let rows: [TitleRow] = (try? await Supa.client
            .from("catches").select("title")
            .eq("id", value: catchId.uuidString).execute().value) ?? []
        return rows.first?.title ?? nil
    }

    /// 폴더 배정(로컬 즉시 반영).
    func setFolder(_ catchId: UUID, folderId: UUID?) {
        var l = loadLocal()
        if let i = l.firstIndex(where: { $0.cloud.id == catchId }) {
            l[i].cloud.folderId = folderId
            saveLocal(l)
        }
    }
}
