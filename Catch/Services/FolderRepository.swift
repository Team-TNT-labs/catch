import Foundation
import Supabase

private struct FolderInsert: Encodable { let owner_id: String; let name: String }
private struct FolderAssign: Encodable { let folder_id: String? }

@MainActor
final class FolderRepository {
    static let shared = FolderRepository()

    func listMine() async -> [Folder] {
        guard let uid = try? await Supa.client.auth.session.user.id else { return [] }
        return (try? await Supa.client.from("folders").select()
            .eq("owner_id", value: uid.uuidString)
            .order("sort").order("created_at")
            .execute().value) ?? []
    }

    func create(name: String) async -> Folder? {
        guard let uid = try? await Supa.client.auth.session.user.id else { return nil }
        return try? await Supa.client.from("folders")
            .insert(FolderInsert(owner_id: uid.uuidString, name: name))
            .select().single().execute().value
    }

    func rename(_ id: UUID, name: String) async {
        _ = try? await Supa.client.from("folders").update(["name": name])
            .eq("id", value: id.uuidString).execute()
    }

    private struct StyleUpdate: Encodable {
        let name: String; let shape: Int?; let color: Int?; let label_color: Int?
    }
    func update(_ id: UUID, name: String, shape: Int?, color: Int?, labelColor: Int?) async {
        _ = try? await Supa.client.from("folders")
            .update(StyleUpdate(name: name, shape: shape, color: color, label_color: labelColor))
            .eq("id", value: id.uuidString).execute()
    }

    func setPublic(_ id: UUID, _ isPublic: Bool) async {
        _ = try? await Supa.client.from("folders").update(["is_public": isPublic])
            .eq("id", value: id.uuidString).execute()
    }

    func delete(_ id: UUID) async {
        // 폴더 삭제 시 내부 캐치는 folder_id가 set null(FK on delete set null)로 미배정 처리됨
        _ = try? await Supa.client.from("folders").delete()
            .eq("id", value: id.uuidString).execute()
    }

    func assign(catchId: UUID, folderId: UUID?) async {
        _ = try? await Supa.client.from("catches")
            .update(FolderAssign(folder_id: folderId?.uuidString))
            .eq("id", value: catchId.uuidString).execute()
    }
}
