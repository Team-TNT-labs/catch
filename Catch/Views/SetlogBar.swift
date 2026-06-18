import SwiftUI

enum CatchMode: String, CaseIterable {
    case camera, jar, friends

    var label: String {
        switch self {
        case .camera: return "camera"
        case .jar: return "jar"
        case .friends: return "friends"
        }
    }
}

/// SETLOG 하단 바 — [둥근버튼] [ camera | jar | friends 세그먼트 ] [둥근버튼]
struct SetlogBottomBar: View {
    @Binding var mode: CatchMode
    var leftIcon: String = "gearshape.fill"
    var rightIcon: String
    var onLeft: () -> Void
    var onRight: () -> Void

    @Namespace private var seg

    var body: some View {
        HStack(spacing: 10) {
            RoundBarButton(icon: leftIcon, action: onLeft)
            segmented
            RoundBarButton(icon: rightIcon, action: onRight)
        }
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(CatchMode.allCases, id: \.self) { m in
                segment(m)
            }
        }
        .padding(4)
        .liquidGlass(Capsule())
    }

    private func segment(_ value: CatchMode) -> some View {
        let selected = mode == value
        return Text(value.label)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(selected ? .white : Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                if selected {
                    Capsule().fill(.white.opacity(0.22))
                        .matchedGeometryEffect(id: "seg", in: seg)
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { mode = value }
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
