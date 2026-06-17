import SwiftUI

/// username 부분 검색 → 프로필 이동.
struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Profile] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List(results) { p in
                NavigationLink(value: p.id) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 36)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.displayName ?? "Catch 사용자").font(.body)
                            Text("@\(p.username ?? "")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if query.count >= 2 && results.isEmpty {
                    ContentUnavailableView("결과 없음", systemImage: "magnifyingglass")
                } else if query.count < 2 {
                    ContentUnavailableView("사용자 검색", systemImage: "magnifyingglass",
                        description: Text("username 2자 이상 입력"))
                }
            }
            .searchable(text: $query, prompt: "username 검색")
            .onChange(of: query) { _, _ in scheduleSearch() }
            .navigationDestination(for: UUID.self) { ProfileView(userId: $0) }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let r = await ProfileRepository.shared.search(query)
            if Task.isCancelled { return }
            results = r
        }
    }
}
