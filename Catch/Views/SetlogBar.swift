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
}

/// SETLOG 하단 바 — [ camera | jar | profile 세그먼트 ]만.
struct SetlogBottomBar: View {
    @Binding var mode: CatchMode

    @Namespace private var seg

    var body: some View {
        segmented
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
