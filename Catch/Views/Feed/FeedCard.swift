import SwiftUI

struct FeedCard: View {
    let row: FeedRow

    @State private var liked: Bool
    @State private var likeCount: Int
    @State private var hidden = false
    @State private var showReport = false
    @State private var showDetail = false

    init(row: FeedRow) {
        self.row = row
        _liked = State(initialValue: row.liked)
        _likeCount = State(initialValue: row.likeCount)
    }

    var body: some View {
        if hidden {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                header
                CachedCatchImage(path: row.bodyPath ?? row.imagePath)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .padding(20)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { showDetail = true }
                footer
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 16)
            .sheet(isPresented: $showDetail) {
                StickerDetailView(
                    catchId: row.id, imagePath: row.imagePath, ownerId: row.ownerId,
                    onClose: { showDetail = false }
                )
                .presentationBackground(.black)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink(value: row.ownerId) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30)).foregroundStyle(Theme.grape)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.displayName ?? "Catch 사용자")
                            .font(.subheadline.bold()).foregroundStyle(Theme.ink)
                        Text("@\(row.username ?? "")")
                            .font(.caption).foregroundStyle(Theme.ink.opacity(0.45))
                    }
                }
            }
            Spacer()
            Menu {
                Button(role: .destructive) { showReport = true } label: {
                    Label("신고", systemImage: "flag")
                }
                Button(role: .destructive) {
                    Task { await ModerationRepository.shared.block(row.ownerId); hidden = true }
                } label: { Label("이 사용자 차단", systemImage: "hand.raised") }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.ink.opacity(0.4)).padding(8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await toggleLike() }
            } label: {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .foregroundStyle(liked ? Theme.coral : Theme.ink.opacity(0.5))
                    .scaleEffect(liked ? 1.1 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: liked)
                Text("\(likeCount)").foregroundStyle(Theme.ink.opacity(0.6)).font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .alert("신고할까요?", isPresented: $showReport) {
            Button("취소", role: .cancel) {}
            Button("신고", role: .destructive) {
                Task {
                    await ModerationRepository.shared.report(catchId: row.id, reason: "user_report")
                    hidden = true
                }
            }
        } message: { Text("부적절한 콘텐츠로 신고하고 더 이상 보지 않아요.") }
    }

    private func toggleLike() async {
        if liked {
            liked = false; likeCount = max(0, likeCount - 1)
            await FeedRepository.shared.unlike(row.id)
        } else {
            liked = true; likeCount += 1
            await FeedRepository.shared.like(row.id)
        }
    }
}
