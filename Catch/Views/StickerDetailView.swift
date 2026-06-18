import SwiftUI

/// 스티커 상세 — 블러 배경 위 가운데 글로우 스티커(예전 포커스 형태).
/// 캡션 말풍선(주인 편집), 하트(즉시 반응), 댓글 버튼(탭 → 인스타식 댓글 시트).
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
    @State private var commentCount = 0
    @State private var preview: [Comment] = []   // 최근 댓글 미리보기
    @State private var showComments = false
    @State private var heartBurst = false   // 더블탭 좋아요 연출

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
        ZStack {
            // 블러 배경(탭하면 닫힘 — 편집 중엔 제외)
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if !editing { onClose() } }

            // 라임 글로우
            Circle()
                .fill(RadialGradient(colors: [Theme.lime.opacity(0.5), .clear],
                                     center: .center, startRadius: 8, endRadius: 280))
                .frame(width: 560, height: 560).blur(radius: 36)
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                captionArea
                stickerImage
                actionRow
                commentPreview
            }
            .padding(.horizontal, 24)
        }
        .task {
            // 캐시 즉시 표시(다시 열 때 깜빡임 없이).
            if let li = FeedRepository.shared.cachedLikeInfo(catchId) { liked = li.liked; likeCount = li.count }
            if let cm = CommentRepository.shared.cached(catchId) { commentCount = cm.count; preview = Array(cm.suffix(2)) }

            // 좋아요/댓글은 서버 catches 행을 요구 — 로컬-퍼스트라 미동기화면 먼저 업로드.
            await CatchRepository.shared.ensureUploaded(catchId)
            if image == nil { image = await loadBordered() }
            caption = await CatchRepository.shared.title(for: catchId) ?? caption
            let info = await FeedRepository.shared.likeInfo(catchId)
            liked = info.liked; likeCount = info.count
            await loadComments()
        }
        .sheet(isPresented: $showComments, onDismiss: { Task { await loadComments() } }) {
            CommentsSheet(catchId: catchId, isOwner: isOwner) { commentCount = $0 }
        }
    }

    // MARK: - Caption bubble

    @ViewBuilder private var captionArea: some View {
        if editing {
            VStack(spacing: 12) {
                TextField("캡션", text: $draft)
                    .font(.callout.weight(.bold)).foregroundStyle(.black).tint(.black)
                    .multilineTextAlignment(.center).lineLimit(1)
                    .focused($captionFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await saveCaption() } }
                    .onChange(of: draft) { _, v in if v.count > 20 { draft = String(v.prefix(20)) } }
                    .modifier(LimeBubble())
                    .onAppear { captionFocused = true }
                HStack(spacing: 20) {
                    Button { editing = false } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                            .frame(width: 42, height: 42).background(Theme.surface, in: Circle())
                    }
                    Button { Task { await saveCaption() } } label: {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 42, height: 42).background(Theme.lime, in: Circle())
                    }
                }
            }
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
            .multilineTextAlignment(.center).lineLimit(1)
            .modifier(LimeBubble())
    }

    // MARK: - Sticker

    private var stickerImage: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                CatchLoader()
            }
        }
        .frame(maxWidth: 300, maxHeight: 340)
        .shadow(color: Theme.lime.opacity(0.5), radius: 24)
        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
        // 인스타식 더블탭 좋아요 + 하트 버스트
        .overlay {
            Image(systemName: "heart.fill")
                .font(.system(size: 96)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 10)
                .scaleEffect(heartBurst ? 1 : 0.5)
                .opacity(heartBurst ? 0.95 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: heartBurst)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { Task { await doubleTapLike() } }
    }

    // MARK: - Actions (heart / comment)

    private var actionRow: some View {
        HStack(spacing: 14) {
            Button { Task { await toggleLike() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 21))
                        .foregroundStyle(liked ? Theme.coral : .white)
                        .animation(.easeInOut(duration: 0.2), value: liked)
                    Text("\(likeCount)").foregroundStyle(.white)
                }
                .font(.title3)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            Button { showComments = true } label: {
                HStack(spacing: 7) {
                    Image("CommentIcon").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 20, height: 20).foregroundStyle(.white)
                    Text("\(commentCount)").foregroundStyle(.white)
                }
                .font(.title3)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder private var commentPreview: some View {
        if !preview.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(preview) { c in
                    (Text("\(c.username ?? "")  ").font(.body.bold()) + Text(c.body).font(.body))
                        .foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                }
                if commentCount > preview.count {
                    Text("댓글 \(commentCount)개 모두 보기")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { showComments = true }
        }
    }

    // MARK: - Logic

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

    /// 더블탭: 하트 버스트 연출 + (아직 안 눌렀으면) 좋아요(인스타처럼 해제는 안 함).
    private func doubleTapLike() async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        heartBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { heartBurst = false }
        if !liked {
            liked = true; likeCount += 1
            await FeedRepository.shared.like(catchId)
        }
    }

    private func loadComments() async {
        let all = await CommentRepository.shared.list(catchId)
        commentCount = all.count
        preview = Array(all.suffix(2))
    }

    private func loadBordered() async -> UIImage? {
        guard let raw = await CatchRepository.shared.image(at: imagePath) else { return nil }
        return await Task.detached(priority: .userInitiated) { raw.whiteStickerBordered().bordered }.value
    }
}

/// 인스타식 댓글 시트 — 목록 + 하단 입력. medium/large 디텐트.
struct CommentsSheet: View {
    let catchId: UUID
    let isOwner: Bool
    var onCountChange: (Int) -> Void

    @State private var comments: [Comment] = []
    @State private var text = ""
    @State private var loading = true
    @FocusState private var focused: Bool

    private let me = Supa.client.auth.currentSession?.user.id

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loading {
                    Spacer(); CatchLoader(); Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    Text("첫 댓글을 남겨보세요").font(.subheadline).foregroundStyle(Theme.muted)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(comments) { c in row(c) }
                        }
                        .padding(16)
                    }
                }
                inputBar
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("댓글").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .task { await reload() }
    }

    private func row(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 40)).foregroundStyle(Theme.grape)
                .offset(y: -3)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.username ?? "").font(.subheadline.bold()).foregroundStyle(Theme.muted)
                Text(c.body).font(.body).foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if c.authorId == me || isOwner {
                Button(role: .destructive) { Task { await delete(c) } } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
            if c.authorId != me {
                Button(role: .destructive) {
                    Task { await ModerationRepository.shared.report(userId: c.authorId, reason: "comment_report") }
                } label: { Label("신고", systemImage: "flag") }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("댓글 달기…", text: $text, axis: .vertical)
                .focused($focused).lineLimit(1...4)
                .font(.system(size: 17))
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .foregroundStyle(Theme.ink)
            // 입력해서 전송 가능할 때만 버튼 등장.
            if !text.trimmed.isEmpty {
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(Theme.lime, in: Circle())
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text.trimmed.isEmpty)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.black)
    }

    private func reload() async {
        comments = await CommentRepository.shared.list(catchId)
        loading = false
        onCountChange(comments.count)
    }

    private func send() async {
        let body = text.trimmed
        guard !body.isEmpty else { return }
        text = ""; focused = false
        if await CommentRepository.shared.add(catchId, body: body) { await reload() }
    }

    private func delete(_ c: Comment) async {
        await CommentRepository.shared.delete(c.id)
        await reload()
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
