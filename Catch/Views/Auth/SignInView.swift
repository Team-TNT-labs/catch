import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "hand.raised.fingers.spread.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
            Text("Catch")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("잡은 사물을 모으고, 나누고, 발견하세요")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 8)
            Spacer()

            Button {
                working = true
                Task { await auth.signInWithApple(); working = false }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    Text("Apple로 계속하기").fontWeight(.semibold)
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(working)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)

            Text("계속하면 서비스 약관 및 개인정보 처리방침에 동의합니다.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay { if working { ProgressView().tint(.white) } }
        .alert("안내", isPresented: Binding(
            get: { auth.errorMessage != nil },
            set: { if !$0 { auth.errorMessage = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(auth.errorMessage ?? "") }
    }
}
