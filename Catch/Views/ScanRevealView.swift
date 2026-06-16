import SwiftUI

/// 촬영한 원본을 스캐너 라인이 위→아래로 훑고, 그 자리에서 누끼(배경 제거)가 드러나는 풀스크린 연출.
/// 누끼(`cutout`)는 원본과 같은 프레임(크롭 안 함)이라 픽셀 단위로 정렬된다.
struct ScanRevealView: View {
    let original: UIImage
    let cutout: UIImage?          // 풀프레임 배경 제거 결과(원본과 정렬). 준비되면 주입.
    var onCatch: () -> Void
    var onRetake: () -> Void

    @State private var linePos: CGFloat = 0      // 스캔 라인 위치 0(상단)~1(하단)
    @State private var reveal: CGFloat = 0       // 누끼 노출 마스크 0~1
    @State private var bgVisible = true          // 원본 배경 표시 여부
    @State private var revealing = false         // 노출 시퀀스 진행 중
    @State private var finished = false          // 스캔 완료
    @State private var showControls = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .top) {
                Color.black

                // 원본 사진 (풀스크린, 노출되며 사라짐)
                Image(uiImage: original)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipped()
                    .opacity(bgVisible ? 1 : 0)

                // 누끼: 위에서부터 reveal 비율만큼 마스킹해 드러냄
                if let cutout {
                    Image(uiImage: cutout)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                        .mask(alignment: .top) {
                            Rectangle().frame(height: h * reveal)
                        }
                }

                // 스캔 라인 (글로우 밴드 + 밝은 선)
                if !finished {
                    scanLine
                        .frame(width: w, height: 64)
                        .offset(y: linePos * h - 32)
                        .allowsHitTesting(false)
                }

                // 하단 컨트롤
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button(action: onRetake) {
                            Label("다시찍기", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Button(action: onCatch) {
                            Label("Catch", systemImage: "hand.raised.fill")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(.white, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                    .opacity(showControls ? 1 : 0)
                    .offset(y: showControls ? 0 : 24)
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .onAppear {
            startScanningLoop()
            if cutout != nil { beginReveal() }
        }
        .onChange(of: cutout != nil) { _, ready in
            if ready, !revealing { beginReveal() }
        }
    }

    private var scanLine: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .cyan.opacity(0.35), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .blur(radius: 8)
            Rectangle()
                .fill(LinearGradient(colors: [.cyan.opacity(0.2), .white, .cyan.opacity(0.2)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 2.5)
                .shadow(color: .cyan, radius: 8)
        }
    }

    /// 처리 중에는 스캔 라인이 위아래로 반복해서 훑는다.
    private func startScanningLoop() {
        linePos = 0
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            linePos = 1
        }
    }

    /// 누끼가 준비되면 한 번의 하강 스윕으로 결과를 드러낸다.
    private func beginReveal() {
        revealing = true
        withAnimation(.easeInOut(duration: 0.2)) { linePos = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 1.2)) {
                linePos = 1
                reveal = 1
            }
            withAnimation(.easeInOut(duration: 0.6).delay(0.75)) { bgVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.easeOut(duration: 0.25)) { finished = true }
                withAnimation(.easeOut(duration: 0.3).delay(0.1)) { showControls = true }
            }
        }
    }
}
