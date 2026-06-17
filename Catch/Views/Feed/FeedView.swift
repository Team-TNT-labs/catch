import SwiftUI

struct FeedView: View {
    @State private var rows: [FeedRow] = []
    @State private var loading = false
    @State private var reachedEnd = false
    @State private var didLoad = false
    @State private var showSearch = false

    private let repo = FeedRepository.shared

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty && !loading && didLoad {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            ForEach(rows) { row in
                                FeedCard(row: row)
                                    .onAppear { maybeLoadMore(row) }
                            }
                            if loading { ProgressView().tint(.white).padding() }
                        }
                        .padding(.vertical, 12)
                    }
                    .refreshable { await reload() }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("피드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .navigationDestination(for: UUID.self) { ProfileView(userId: $0) }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task { if !didLoad { await reload() } }
        .sheet(isPresented: $showSearch) { UserSearchView() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 44)).foregroundStyle(.white.opacity(0.4))
            Text("아직 피드가 비어 있어요")
                .font(.headline).foregroundStyle(.white)
            Text("사람을 검색해 팔로우하면\n그들의 수집이 여기 모여요")
                .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button { showSearch = true } label: {
                Label("사람 찾기", systemImage: "magnifyingglass")
                    .font(.subheadline.bold()).foregroundStyle(.black)
                    .padding(.horizontal, 20).frame(height: 44)
                    .background(.white, in: Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        loading = true
        let page = await repo.page(after: nil)
        rows = page
        reachedEnd = page.count < 20
        loading = false
        didLoad = true
    }

    private func maybeLoadMore(_ row: FeedRow) {
        guard !loading, !reachedEnd, row.id == rows.last?.id else { return }
        Task {
            loading = true
            let page = await repo.page(after: rows.last)
            rows.append(contentsOf: page)
            reachedEnd = page.count < 20
            loading = false
        }
    }
}
