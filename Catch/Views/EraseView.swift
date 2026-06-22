import SwiftUI

/// 누끼가 깔끔하지 않을 때 손가락으로 불필요한 부분을 지우는 도구.
/// - 확정된 지움은 비트맵(`working`)에 구워두고, 라이브로는 진행 중인 한 획만 그려 가볍게.
/// - 제스처는 명시적 좌표공간("edit")으로 받아 이미지 사각형 기준으로 정확히 매핑.
struct EraseView: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    @State private var working: UIImage           // 지금까지 지운 결과(비트맵)
    @State private var current: [CGPoint] = []     // 진행 중 한 획(이미지 사각형 로컬 좌표)
    @State private var undo: [UIImage] = []        // 되돌리기 스냅샷
    @State private var brush: CGFloat = 26

    init(image: UIImage, onDone: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.onDone = onDone
        self.onCancel = onCancel
        _working = State(initialValue: image)
    }

    var body: some View {
        GeometryReader { geo in
            let rect = fittedRect(image.size, in: geo.size)

            ZStack {
                Color.black.ignoresSafeArea()

                ZStack {
                    CheckerBackground()
                    Image(uiImage: working).resizable()
                        .overlay {
                            Canvas { ctx, _ in draw(current, in: &ctx) }
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

                VStack {
                    topBar
                    Spacer()
                    bottomBar(displayWidth: rect.width)
                }
                .padding(.horizontal, 20)
                .padding(.top, deviceSafeAreaTop)
                .padding(.bottom, deviceSafeAreaBottom + 8)
            }
            // 전체화면에서 제스처를 받고, edit 좌표를 이미지 사각형 로컬로 변환.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("edit"))
                    .onChanged { v in
                        let p = CGPoint(x: v.location.x - rect.minX, y: v.location.y - rect.minY)
                        if let last = current.last, hypot(p.x - last.x, p.y - last.y) < 1.5 { return }
                        current.append(p)
                    }
                    .onEnded { _ in commit(displayWidth: rect.width) }
            )
        }
        .coordinateSpace(name: "edit")
        .ignoresSafeArea()
    }

    // MARK: - Drawing

    private func draw(_ stroke: [CGPoint], in ctx: inout GraphicsContext) {
        guard let first = stroke.first else { return }
        if stroke.count == 1 {
            ctx.fill(Path(ellipseIn: CGRect(x: first.x - brush, y: first.y - brush,
                                            width: brush * 2, height: brush * 2)),
                     with: .color(.black))
        } else {
            var p = Path(); p.addLines(stroke)
            ctx.stroke(p, with: .color(.black),
                       style: StrokeStyle(lineWidth: brush * 2, lineCap: .round, lineJoin: .round))
        }
    }

    /// 진행 중 획을 working 비트맵에 네이티브 해상도로 굽고 라이브 획은 비운다.
    private func commit(displayWidth: CGFloat) {
        guard !current.isEmpty, displayWidth > 0 else { current = []; return }
        undo.append(working)
        working = bake(stroke: current, into: working, displayWidth: displayWidth)
        current = []
    }

    private func bake(stroke: [CGPoint], into base: UIImage, displayWidth: CGFloat) -> UIImage {
        let scale = base.size.width / displayWidth
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = base.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: base.size, format: format).image { c in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            let cg = c.cgContext
            cg.setBlendMode(.clear)
            cg.setLineCap(.round); cg.setLineJoin(.round)
            cg.setLineWidth(brush * 2 * scale)
            guard let first = stroke.first else { return }
            if stroke.count == 1 {
                let r = brush * scale
                cg.fillEllipse(in: CGRect(x: first.x * scale - r, y: first.y * scale - r, width: r * 2, height: r * 2))
            } else {
                cg.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                for p in stroke.dropFirst() { cg.addLine(to: CGPoint(x: p.x * scale, y: p.y * scale)) }
                cg.strokePath()
            }
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            Button("취소") { onCancel() }.foregroundStyle(.white)
            Spacer()
            Button {
                if let last = undo.popLast() { working = last }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(undo.isEmpty ? .white.opacity(0.35) : .white)
            }
            .disabled(undo.isEmpty)
        }
        .font(.headline)
    }

    private func bottomBar(displayWidth: CGFloat) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            Slider(value: $brush, in: 12...56).tint(Theme.lime)
            Button {
                onDone(working)
            } label: {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(Theme.lime, in: Circle())
            }
        }
    }
}

/// 이미지 종횡비를 박스 안에 맞춘(aspect fit) 사각형(상/하단 바 여유 포함).
private func fittedRect(_ imageSize: CGSize, in box: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: box) }
    let pad: CGFloat = 24
    let avail = CGSize(width: box.width - pad * 2, height: box.height - 220)
    let imgAspect = imageSize.width / imageSize.height
    let boxAspect = avail.width / max(1, avail.height)
    let size: CGSize = imgAspect > boxAspect
        ? CGSize(width: avail.width, height: avail.width / imgAspect)
        : CGSize(width: avail.height * imgAspect, height: avail.height)
    return CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
                  width: size.width, height: size.height)
}

/// 투명 영역 표시용 체커 배경.
private struct CheckerBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 14
            let cols = Int(size.width / s) + 1, rows = Int(size.height / s) + 1
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s)),
                             with: .color(.white.opacity(0.10)))
                }
            }
        }
    }
}
