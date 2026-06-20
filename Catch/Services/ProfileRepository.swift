import Foundation
import UIKit
import Supabase

private struct FollowRow: Decodable { let follower_id: UUID }

/// 프로필 검색·카운트·팔로우·아바타.
@MainActor
final class ProfileRepository {
    static let shared = ProfileRepository()

    private let avatarBucket = "avatars"
    private let fm = FileManager.default
    private var avatarMemoryCache: [String: UIImage] = [:]

    // MARK: - 팔로잉 목록
    func following() async -> [Profile] {
        (try? await Supa.client.rpc("following_profiles").execute().value) ?? []
    }

    // MARK: - 아바타
    private struct AvatarUpdate: Encodable { let avatar_url: String? }

    /// 아바타 업로드(교체) → 경로를 profiles.avatar_url에 저장. 성공 시 새 경로 반환.
    @discardableResult
    func uploadAvatar(_ image: UIImage) async -> String? {
        guard let uid = try? await Supa.client.auth.session.user.id else { return nil }
        let square = image.orientationNormalized().squareCropped().resized(maxDimension: 512)
        guard let data = square.jpegData(compressionQuality: 0.85) else { return nil }
        let path = "avatars/\(uid.uuidString.lowercased())/avatar.jpg"
        do {
            try await Supa.client.storage.from(avatarBucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            try await Supa.client.from("profiles").update(AvatarUpdate(avatar_url: path))
                .eq("id", value: uid.uuidString).execute()
            avatarMemoryCache[path] = square
            try? data.write(to: avatarCacheURL(path))
            return path
        } catch {
            Log.data.error("avatar upload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 아바타 삭제(스토리지 + avatar_url null).
    func removeAvatar() async {
        guard let uid = try? await Supa.client.auth.session.user.id else { return }
        let path = "avatars/\(uid.uuidString.lowercased())/avatar.jpg"
        _ = try? await Supa.client.storage.from(avatarBucket).remove(paths: [path])
        _ = try? await Supa.client.from("profiles").update(AvatarUpdate(avatar_url: nil))
            .eq("id", value: uid.uuidString).execute()
        avatarMemoryCache[path] = nil
        try? fm.removeItem(at: avatarCacheURL(path))
    }

    /// 아바타 이미지 로드(메모리/디스크 캐시 우선).
    func avatarImage(path: String) async -> UIImage? {
        if let img = avatarMemoryCache[path] { return img }
        let url = avatarCacheURL(path)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            avatarMemoryCache[path] = img; return img
        }
        guard let data = try? await Supa.client.storage.from(avatarBucket).download(path: path),
              let img = UIImage(data: data) else { return nil }
        try? data.write(to: url)
        avatarMemoryCache[path] = img
        return img
    }

    private func avatarCacheURL(_ path: String) -> URL {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatars", isDirectory: true)
        if !fm.fileExists(atPath: base.path) { try? fm.createDirectory(at: base, withIntermediateDirectories: true) }
        return base.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    func search(_ query: String) async -> [Profile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let me = try? await Supa.client.auth.session.user.id
        let results: [Profile] = (try? await Supa.client
            .from("profiles").select()
            .ilike("username", pattern: "%\(q)%")
            .limit(20)
            .execute().value) ?? []
        return results.filter { $0.id != me }   // 본인 제외
    }

    func profile(id: UUID) async -> Profile? {
        try? await Supa.client.from("profiles").select().eq("id", value: id.uuidString)
            .single().execute().value
    }

    func counts(_ userId: UUID) async -> ProfileCounts? {
        let rows: [ProfileCounts]? = try? await Supa.client
            .rpc("profile_counts", params: ["p_user": userId.uuidString])
            .execute().value
        return rows?.first
    }

    func isFollowing(_ target: UUID) async -> Bool {
        guard let me = try? await Supa.client.auth.session.user.id else { return false }
        let rows: [FollowRow] = (try? await Supa.client
            .from("follows").select("follower_id")
            .eq("follower_id", value: me.uuidString)
            .eq("followee_id", value: target.uuidString)
            .execute().value) ?? []
        return !rows.isEmpty
    }

    func follow(_ target: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("follows")
            .insert(["follower_id": me.uuidString, "followee_id": target.uuidString])
            .execute()
    }

    func unfollow(_ target: UUID) async {
        guard let me = try? await Supa.client.auth.session.user.id else { return }
        _ = try? await Supa.client.from("follows").delete()
            .eq("follower_id", value: me.uuidString)
            .eq("followee_id", value: target.uuidString)
            .execute()
    }
}
