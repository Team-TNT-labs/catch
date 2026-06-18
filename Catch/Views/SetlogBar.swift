import SwiftUI

enum CatchMode: String, CaseIterable {
    case camera, jar, profile

    var label: String {
        switch self {
        case .camera: return "camera"
        case .jar: return "jar"
        case .profile: return "profile"
        }
    }

    /// 하찮고 귀여운 아이콘.
    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .jar: return "shippingbox.fill"
        case .profile: return "face.smiling.inverse"
        }
    }
}

/// 완전 커스텀 하단 바 — 다크 알약 + 테마 라임 라인 + 하찮은 아이콘.
/// 탭으로 전환, 바 위에서 드래그해도 전환(iOS 26 탭바처럼).
struct SetlogBottomBar: View {
    @Binding var selection: CatchMode?

    @Namespace private var seg
    @State private var pillWidth: CGFloat = 0
    private let modes = CatchMode.allCases

    var body: some View {
        HStack(spacing: 6) {
            ForEach(modes, id: \.self) { segment($0) }
        }
        .padding(8)
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
            .frame(width: 62, height: 48)
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
