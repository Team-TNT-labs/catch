import SwiftUI

enum CatchMode: String { case camera, jar }

/// SETLOG 하단 바 — [둥근버튼] [ camera | jar 세그먼트 ] [둥근버튼]
struct SetlogBottomBar: View {
    @Binding var mode: CatchMode
    var leftIcon: String = "person.fill"
    var rightIcon: String
    var onLeft: () -> Void
    var onRight: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundBarButton(icon: leftIcon, action: onLeft)
            segmented
            RoundBarButton(icon: rightIcon, action: onRight)
        }
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            segment("camera", .camera)
            segment("jar", .jar)
        }
        .padding(4)
        .liquidGlass(Capsule())
    }

    private func segment(_ title: String, _ value: CatchMode) -> some View {
        let selected = mode == value
        return Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(selected ? .white : Theme.muted)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background {
                if selected { Capsule().fill(.white.opacity(0.22)) }
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { mode = value }
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
