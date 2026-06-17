import SwiftUI

struct FoldersView: View {
    var onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var folders: [Folder] = []
    @State private var catches: [CloudCatch] = []
    @State private var newName = ""
    @State private var assignTarget: CloudCatch?

    private let frepo = FolderRepository.shared
    private let crepo = CatchRepository.shared

    private let cols = [GridItem(.adaptive(minimum: 70), spacing: 8)]

    var body: some View {
        NavigationStack {
            List {
                Section("폴더") {
                    ForEach(folders) { f in
                        HStack {
                            Text(f.name)
                            Spacer()
                            Button {
                                Task { await frepo.setPublic(f.id, !f.isPublic); await reload() }
                            } label: {
                                Image(systemName: f.isPublic ? "globe" : "lock.fill")
                                    .foregroundStyle(f.isPublic ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await frepo.delete(f.id); await reload(); onChanged() }
                            } label: { Label("삭제", systemImage: "trash") }
                        }
                    }
                    HStack {
                        TextField("새 폴더 이름", text: $newName)
                        Button("추가") {
                            let name = newName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            newName = ""
                            Task { _ = await frepo.create(name: name); await reload() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("수집 정리 — 탭해서 폴더 지정") {
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(catches) { c in
                            CachedCatchImage(path: c.bodyPath ?? c.imagePath)
                                .frame(width: 70, height: 70)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .bottomTrailing) {
                                    if c.folderId != nil {
                                        Image(systemName: "folder.fill")
                                            .font(.caption2).foregroundStyle(.white)
                                            .padding(3).background(.black.opacity(0.5), in: Circle())
                                            .padding(3)
                                    }
                                }
                                .onTapGesture { assignTarget = c }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("폴더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .confirmationDialog("폴더 지정", isPresented: Binding(
                get: { assignTarget != nil }, set: { if !$0 { assignTarget = nil } }
            ), titleVisibility: .visible) {
                Button("미배정") { assign(nil) }
                ForEach(folders) { f in Button(f.name) { assign(f.id) } }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        folders = await frepo.listMine()
        catches = (try? await crepo.loadMine()) ?? []
    }

    private func assign(_ folderId: UUID?) {
        guard let target = assignTarget else { return }
        assignTarget = nil
        Task {
            await frepo.assign(catchId: target.id, folderId: folderId)
            await reload()
            onChanged()
        }
    }
}
