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

    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .jar: return "archivebox.fill"
        case .profile: return "person.fill"
        }
    }
}

/// SETLOG 하단 바 — 아이콘 세그먼트. 탭/드래그로 전환(iOS 26 탭바처럼).
struct SetlogBottomBar: View {
    @Binding var selection: CatchMode?

    @Namespace private var seg
    @State private var pillWidth: CGFloat = 0
    private let modes = CatchMode.allCases

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modes, id: \.self) { segment($0) }
        }
        .padding(4)
        .liquidGlass(Capsule())
        .background(
            GeometryReader { g in
                Color.clear.onAppear { pillWidth = g.size.width }
            }
        )
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard pillWidth > 0 else { return }
                    let i = max(0, min(modes.count - 1,
                                       Int(v.location.x / (pillWidth / CGFloat(modes.count)))))
                    let m = modes[i]
                    if selection != m {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { selection = m }
                    }
                }
        )
    }

    private func segment(_ value: CatchMode) -> some View {
        let selected = selection == value
        return Image(systemName: value.icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(selected ? .white : Theme.muted)
            .frame(width: 54, height: 38)
            .background {
                if selected {
                    Capsule().fill(.white.opacity(0.22))
                        .matchedGeometryEffect(id: "seg", in: seg)
                }
            }
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
