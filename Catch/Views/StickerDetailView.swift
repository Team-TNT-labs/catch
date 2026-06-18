import SwiftUI

/// 스티커 상세 — 캡션(말풍선, 주인 편집) + 좋아요 + 댓글.
/// 항아리(내 스티커)와 피드(타인 스티커) 양쪽에서 동일하게 쓰인다.
struct StickerDetailView: View {
    let catchId: UUID
    let imagePath: String
    let ownerId: UUID
    var initialTitle: String?
    var preloaded: UIImage?
    var onClose: () -> Void

    @State private var image: UIImage?
    @State private var caption: String
    @State private var editing = false
    @State private var draft = ""

    @State private var liked = false
    @State private var likeCount = 0

    @State private var comments: [Comment] = []
    @State private var commentText = ""
    @State private var loadingComments = true

    @FocusState private var commentFocused: Bool
    @FocusState private var captionFocused: Bool

    private let me = Supa.client.auth.currentSession?.user.id
    private var isOwner: Bool { me == ownerId }

    init(catchId: UUID, imagePath: String, ownerId: UUID,
         initialTitle: String? = nil, preloaded: UIImage? = nil, onClose: @escaping () -> Void) {
        self.catchId = catchId; self.imagePath = imagePath; self.ownerId = ownerId
        self.initialTitle = initialTitle; self.preloaded = preloaded; self.onClose = onClose
        _caption = State(initialValue: initialTitle ?? "")
        _image = State(initialValue: preloaded)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    captionArea
                    sticker
                    likeRow
                    Divider().overlay(Theme.muted.opacity(0.25))
                    commentsList
                }
                .padding(16)
            }
            commentInput
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            if image == nil { image = await loadBordered() }
            caption = await CatchRepository.shared.title(for: catchId) ?? caption
            let info = await FeedRepository.shared.likeInfo(catchId)
            liked = info.liked; likeCount = info.count
            await reloadComments()
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36).background(Theme.surface, in: Circle())
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 2)
    }

    // MARK: - Caption bubble

    @ViewBuilder private var captionArea: some View {
        if editing {
            VStack(spacing: 10) {
                // 편집 중에도 동일한 라임 타원 모양 유지(모양이 바뀌지 않도록).
                TextField("캡션", text: $draft)
                    .font(.callout.weight(.bold)).foregroundStyle(.black).tint(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .focused($captionFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await saveCaption() } }
                    .onChange(of: draft) { _, v in if v.count > 20 { draft = String(v.prefix(20)) } }
                    .modifier(LimeBubble())
                    .onAppear { captionFocused = true }
                HStack(spacing: 20) {
                    Button { editing = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                            .frame(width: 42, height: 42).background(Theme.surface, in: Circle())
                    }
                    Button { Task { await saveCaption() } } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 42, height: 42).background(Theme.lime, in: Circle())
                    }
                }
            }
            .padding(.top, 2)
        } else if !caption.isEmpty {
            Button { if isOwner { startEdit() } } label: { bubble(caption) }
                .buttonStyle(.plain).allowsHitTesting(isOwner)
        } else if isOwner {
            Button { startEdit() } label: { bubble("＋ 캡션 추가", muted: true) }.buttonStyle(.plain)
        }
    }

    private func bubble(_ text: String, muted: Bool = false) -> some View {
        Text(text)
            .font(.callout.weight(.bold))
            .foregroundStyle(muted ? Color.black.opacity(0.4) : .black)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .modifier(LimeBubble())
            .padding(.top, 2)
    }

    // MARK: - Sticker

    private var sticker: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                CatchLoader()
            }
        }
        .frame(maxWidth: .infinity).frame(height: 230)
        .padding(.top, 20)
    }

    // MARK: - Like

    private var likeRow: some View {
        HStack(spacing: 16) {
            Button { Task { await toggleLike() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? Theme.coral : Theme.muted)
                        .scaleEffect(liked ? 1.1 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: liked)
                    Text("\(likeCount)").foregroundStyle(Theme.ink.opacity(0.7))
                }.font(.headline)
            }
            HStack(spacing: 6) {
                Image(systemName: "bubble.right").foregroundStyle(Theme.muted)
                Text("\(comments.count)").foregroundStyle(Theme.ink.opacity(0.7))
            }.font(.headline)
            Spacer()
        }
    }

    // MARK: - Comments

    private var commentsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loadingComments {
                CatchLoader(size: 6, color: .white.opacity(0.35)).frame(maxWidth: .infinity)
            } else if comments.isEmpty {
                Text("첫 댓글을 남겨보세요").font(.subheadline).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
            } else {
                ForEach(comments) { c in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(c.username ?? "")").font(.caption.bold()).foregroundStyle(Theme.muted)
                            Text(c.body).font(.subheadline).foregroundStyle(Theme.ink)
                        }
                        Spacer()
                        if c.authorId == me || isOwner {
                            Button { Task { await deleteComment(c) } } label: {
                                Image(systemName: "trash").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commentInput: some View {
        HStack(spacing: 10) {
            TextField("댓글 달기…", text: $commentText, axis: .vertical)
                .focused($commentFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .foregroundStyle(Theme.ink)
            Button { Task { await sendComment() } } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(commentText.trimmed.isEmpty ? Theme.muted : Theme.lime)
            }
            .disabled(commentText.trimmed.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.black)
    }

    // MARK: - Actions

    private func startEdit() { draft = caption; editing = true }

    private func saveCaption() async {
        let value = draft.trimmed
        caption = value
        editing = false
        await CatchRepository.shared.setTitle(catchId, value)
    }

    private func toggleLike() async {
        if liked { liked = false; likeCount = max(0, likeCount - 1); await FeedRepository.shared.unlike(catchId) }
        else { liked = true; likeCount += 1; await FeedRepository.shared.like(catchId) }
    }

    private func sendComment() async {
        let body = commentText.trimmed
        guard !body.isEmpty else { return }
        commentText = ""
        commentFocused = false
        if await CommentRepository.shared.add(catchId, body: body) {
            await reloadComments()
        }
    }

    private func deleteComment(_ c: Comment) async {
        await CommentRepository.shared.delete(c.id)
        await reloadComments()
    }

    private func reloadComments() async {
        comments = await CommentRepository.shared.list(catchId)
        loadingComments = false
    }

    private func loadBordered() async -> UIImage? {
        guard let raw = await CatchRepository.shared.image(at: imagePath) else { return nil }
        return await Task.detached(priority: .userInitiated) { raw.whiteStickerBordered().bordered }.value
    }
}

/// 캡션 말풍선 스타일 — 라임 타원 + 흰 테두리(표시·편집 공통으로 모양 유지).
private struct LimeBubble: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 18, leading: 34, bottom: 18, trailing: 34))
            .frame(maxWidth: 300)
            .background(
                Ellipse()
                    .fill(Theme.lime)
                    .overlay(Ellipse().strokeBorder(.white, lineWidth: 7))
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
