import SwiftUI

enum CatchMode: String, CaseIterable {
    case camera, jar   // groups (그룹 탭은 UX 개선 후 재도입 — 아래 주석 참고)

    var label: String {
        switch self {
        case .camera: return "camera"
        case .jar: return "jar"
        // case .groups: return "groups"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .jar: return "face.smiling.inverse"   // 스티커 항아리 = 웃는 얼굴
        // case .groups: return "person.2.fill"    // 공유 그룹(보류)
        }
    }
}

/// 완전 커스텀 하단 바 — 다크 알약 + 테마 라임 라인 + 하찮은 아이콘.
/// 탭으로 전환, 바 위에서 드래그해도 전환(iOS 26 탭바처럼).
struct SetlogBottomBar: View {
    // ── 외형 치수 ── 물리 바리어를 실제 보이는 알약과 정확히 맞추는 데 쓴다.
    static let segW: CGFloat = 62
    static let segH: CGFloat = 48
    static let segGap: CGFloat = 6
    static let barPadding: CGFloat = 8
    /// 보이는 알약 전체 폭 = 세그먼트들 + 간격 + 좌우 패딩 (활성 탭 수 기준 자동 계산).
    static var pillWidth: CGFloat {
        let n = CGFloat(CatchMode.allCases.count)
        return n * segW + max(0, n - 1) * segGap + barPadding * 2
    }
    /// 보이는 알약 전체 높이 = 세그먼트 높이 + 상하 패딩.
    static var pillHeight: CGFloat { segH + barPadding * 2 }

    @Binding var selection: CatchMode?

    @Namespace private var seg
    @State private var pillWidth: CGFloat = 0
    private let modes = CatchMode.allCases

    var body: some View {
        HStack(spacing: Self.segGap) {
            ForEach(modes, id: \.self) { segment($0) }
        }
        .padding(Self.barPadding)
        .background(Capsule().fill(Color.black.opacity(0.9)))
        .overlay(Capsule().strokeBorder(Theme.lime, lineWidth: 2.5))   // 테마 라임 라인
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { pillWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in pillWidth = w }
            }
        )
        .contentShape(Capsule())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in
                    guard pillWidth > 0 else { return }
                    let i = max(0, min(modes.count - 1,
                                       Int(v.location.x / (pillWidth / CGFloat(modes.count)))))
                    select(modes[i])
                }
        )
    }

    private func segment(_ value: CatchMode) -> some View {
        let selected = selection == value
        return Image(systemName: value.icon)
            .font(.system(size: 21, weight: .bold))
            .foregroundStyle(selected ? .black : Theme.lime)
            .frame(width: Self.segW, height: Self.segH)
            .background {
                if selected {
                    Capsule().fill(Theme.lime)
                        .matchedGeometryEffect(id: "seg", in: seg)
                }
            }
            .contentShape(Capsule())
            .onTapGesture { select(value) }
    }

    private func select(_ m: CatchMode) {
        guard selection != m else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { selection = m }
    }
}

struct RoundBarButton: View {
    let icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .liquidGlass(Circle(), interactive: true)
        }
    }
}
