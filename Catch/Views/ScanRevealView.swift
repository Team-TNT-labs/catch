import SwiftUI

/// 촬영 원본을 라임 빛이 위→아래로 부드럽게 훑으며, 그 자리에서 누끼(배경 제거)가 떠오르는 풀스크린 연출.
/// 누끼(`cutout`)는 원본과 같은 프레임(크롭 안 함)이라 픽셀 단위로 정렬된다.
struct ScanRevealView: View {
    let original: UIImage
    let cutout: UIImage?          // 풀프레임 배경 제거 결과(원본과 정렬). 준비되면 주입.
    var onCatch: (UIImage) -> Void   // 저장할 누끼(다듬기로 편집됐을 수 있음)
    var onRetake: () -> Void

    @State private var beam: CGFloat = 0         // 스캔 빛 위치 0(상단)~1(하단)
    @State private var reveal: CGFloat = 0       // 누끼 노출 0~1
    @State private var bgOpacity: CGFloat = 1    // 원본 배경 페이드
    @State private var bloom: CGFloat = 0        // 완료 시 은은한 라임 발광
    @State private var finished = false          // 스캔 완료(빛 숨김)
    @State private var revealing = false
    @State private var showControls = false
    @State private var subject: UIImage?         // 트림된 누끼(저장·편집 대상)
    @State private var bordered: UIImage?        // 흰 테두리 입힌 스티커(완료 시 페이드인)
    @State private var editing = false           // 지우개 편집 중

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .top) {
                Color.black

                // 원본 — 드러나며 부드럽게 사라짐
                Image(uiImage: original)
                    .resizable().scaledToFill()
                    .frame(width: w, height: h).clipped()
                    .opacity(bgOpacity)

                // 누끼 — 위에서부터 reveal 비율만큼 마스킹해 떠오름(원본과 정합 유지)
                if let cutout {
                    Image(uiImage: cutout)
                        .resizable().scaledToFill()
                        .frame(width: w, height: h).clipped()
                        .mask(alignment: .top) { Rectangle().frame(height: h * reveal) }
                        .opacity(finished ? 0 : 1)   // 완료 시 풀프레임 누끼는 사라지고 테두리 스티커만 검정 위에 남김
                }

                // 완료 순간 흰색 테두리 스티커가 가운데로 떠오름(잡으면 항아리에서 보일 모습 그대로).
                if let bordered {
                    Image(uiImage: bordered)
                        .resizable().scaledToFit()
                        .padding(48)
                        .frame(width: w, height: h)
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
                        .opacity(finished ? 1 : 0)
                        .scaleEffect(finished ? 1 : 0.94)
                }

                // 완료 순간 화면 전체에 스며드는 은은한 라임 블룸
                Theme.lime.opacity(0.12 * bloom)
                    .blendMode(.screen)
                    .allowsHitTesting(false)

                // 라임 스캔 빛 — 넓고 부드러운 글로우 + 가는 코어(날카로움 제거)
                if !finished {
                    beamView
                        .frame(width: w, height: 140)
                        .offset(y: beam * h - 70)
                        .allowsHitTesting(false)
                }

                controls

                // 지우개 편집(스캔 위에 전체화면으로)
                if editing, let subject {
                    EraseView(
                        image: subject,
                        onDone: { edited in
                            self.subject = edited            // 즉시 반영(저장 시 capture가 트림)
                            withAnimation { editing = false }
                            // 지워서 비워진 여백을 잘라내 남은 내용에 딱 맞게(투명 레이어 제거).
                            Task.detached(priority: .userInitiated) {
                                let trimmed = edited.trimmingTransparentPixels()
                                let b = trimmed.whiteStickerBordered().bordered
                                await MainActor.run { self.subject = trimmed; self.bordered = b }
                            }
                        },
                        onCancel: { withAnimation { editing = false } }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .onAppear {
            startProcessing()
            if let cutout { prepareSticker(cutout); beginReveal() }
        }
        .onChange(of: cutout != nil) { _, ready in
            guard ready, let cutout else { return }
            prepareSticker(cutout)
            if !revealing { beginReveal() }
        }
    }

    /// 트림된 누끼(저장·편집 대상)와 흰 테두리 스티커(완료 표시용)를 백그라운드에서 미리 만든다.
    private func prepareSticker(_ image: UIImage) {
        guard subject == nil else { return }
        Task.detached(priority: .userInitiated) {
            // 항아리 스티커와 동일하게: 투명 여백을 트림한 뒤 테두리(여백 기준 두꺼운 테두리 방지).
            let trimmed = image.trimmingTransparentPixels()
            let b = trimmed.whiteStickerBordered().bordered
            await MainActor.run { subject = trimmed; bordered = b }
        }
    }

    /// 부드러운 라임 빛 — 넓은 글로우 밴드 + 은은히 발광하는 가는 코어.
    private var beamView: some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, Theme.lime.opacity(0.16), Theme.lime.opacity(0.05), .clear],
                    startPoint: .top, endPoint: .bottom))
                .blur(radius: 20)
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, Theme.lime.opacity(0.85), .clear],
                    startPoint: .leading, endPoint: .trailing))
                .frame(height: 1.5)
                .blur(radius: 0.5)
                .shadow(color: Theme.lime.opacity(0.5), radius: 8)
        }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            Spacer()
            // 누끼가 깔끔하지 않을 때 손으로 다듬기
            if subject != nil {
                Button { withAnimation { editing = true } } label: {
                    Image(systemName: "eraser")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 52, height: 52).background(.ultraThinMaterial, in: Circle())
                }
            }
            HStack(spacing: 30) {
                Button(action: onRetake) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 25, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(.ultraThinMaterial, in: Circle())
                }
                Button { onCatch(subject ?? cutout ?? original) } label: {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 27, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 72, height: 72).background(Theme.lime, in: Circle())
                }
            }
            .padding(.bottom, 44)
        }
        .opacity(showControls ? 1 : 0)
        .offset(y: showControls ? 0 : 24)
    }

    /// 처리 중: 라임 빛이 천천히·부드럽게 오르내린다(경박한 왕복 대신 잔잔하게).
    private func startProcessing() {
        beam = 0.04
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            beam = 0.96
        }
    }

    /// 누끼가 준비되면 한 번의 느린 하강으로 우아하게 드러낸다.
    private func beginReveal() {
        revealing = true
        withAnimation(.easeInOut(duration: 0.3)) { beam = 0 }   // 빛을 상단으로 모음
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeInOut(duration: 1.5)) {           // 단일 느린 하강 + 동기 노출
                beam = 1
                reveal = 1
            }
            withAnimation(.easeIn(duration: 0.9).delay(0.6)) { bgOpacity = 0 }   // 배경 천천히 소멸
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.easeOut(duration: 0.3)) { finished = true }
                // 은은한 라임 블룸 펄스(완료 강조)
                withAnimation(.easeOut(duration: 0.25)) { bloom = 1 }
                withAnimation(.easeIn(duration: 0.7).delay(0.25)) { bloom = 0 }
                withAnimation(.easeOut(duration: 0.35).delay(0.15)) { showControls = true }
            }
        }
    }
}
