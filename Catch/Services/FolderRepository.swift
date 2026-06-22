import Foundation

/// 로컬 폴더 저장(folders.json). 로컬 앱이라 계정 없이 기기에 보관.
@MainActor
final class FolderRepository {
    static let shared = FolderRepository()

    private let fm = FileManager.default
    private var url: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("folders.json")
    }
    private func load() -> [Folder] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Folder].self, from: data) else { return [] }
        return list.sorted { $0.sort < $1.sort }
    }
    private func save(_ list: [Folder]) {
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
    }

    func listMine() async -> [Folder] { load() }

    @discardableResult
    func create(name: String) async -> Folder? {
        var l = load()
        let f = Folder(id: UUID(), name: name, isPublic: false, sort: l.count,
                       shape: 0, color: 0, labelColor: 0)
        l.append(f); save(l)
        return f
    }

    func rename(_ id: UUID, name: String) async {
        var l = load()
        if let i = l.firstIndex(where: { $0.id == id }) { l[i].name = name; save(l) }
    }

    func update(_ id: UUID, name: String, shape: Int?, color: Int?, labelColor: Int?) async {
        var l = load()
        if let i = l.firstIndex(where: { $0.id == id }) {
            l[i].name = name; l[i].shape = shape; l[i].color = color; l[i].labelColor = labelColor
            save(l)
        }
    }

    func setPublic(_ id: UUID, _ isPublic: Bool) async {
        var l = load()
        if let i = l.firstIndex(where: { $0.id == id }) { l[i].isPublic = isPublic; save(l) }
    }

    func delete(_ id: UUID) async {
        save(load().filter { $0.id != id })
        // 폴더 내부 캐치는 미분류(folderId=nil)로 되돌림.
        for c in CatchRepository.shared.localCatches(inFolder: id) {
            CatchRepository.shared.setFolder(c.id, folderId: nil)
        }
    }

    /// 캐치를 폴더에 배정(로컬). 그룹 동기화는 별도.
    func assign(catchId: UUID, folderId: UUID?) async {
        CatchRepository.shared.setFolder(catchId, folderId: folderId)
    }

    /// 백업 복원 — 들어온 폴더를 기존과 병합(중복 id 제외).
    func restore(_ incoming: [Folder]) async {
        var l = load()
        let ids = Set(l.map { $0.id })
        for f in incoming where !ids.contains(f.id) { l.append(f) }
        save(l)
    }

    /// (그룹 기능 보류) 타 유저 폴더 — 로컬 앱에선 없음.
    func listUser(_ userId: UUID) async -> [Folder] { [] }
}
