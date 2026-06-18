import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 로고 (Assets의 CatchLogo, 없으면 텍스트 폴백)
            if UIImage(named: "CatchLogo") != nil {
                Image("CatchLogo")
                    .resizable().scaledToFit()
                    .frame(height: 72)
                    .padding(.horizontal, 48)
            } else {
                Text("catch")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundStyle(Theme.lime)
            }
            Text("collect the world, sticker by sticker.")
                .font(.mono(13))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)

            Spacer()

            Button {
                working = true
                Task { await auth.signInWithApple(); working = false }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                    Text("Connect with Apple").fontWeight(.bold)
                }
            }
            .buttonStyle(CuteButtonStyle(bg: .white, fg: .black))
            .disabled(working)
            .padding(.horizontal, 24)

            Text("having trouble signing in?")
                .font(.mono(11))
                .underline()
                .foregroundStyle(Theme.muted)
                .padding(.top, 18)
                .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay { if working { ProgressView().tint(Theme.coral) } }
        .alert("안내", isPresented: Binding(
            get: { auth.errorMessage != nil },
            set: { if !$0 { auth.errorMessage = nil } }
        )) { Button("확인", role: .cancel) {} } message: { Text(auth.errorMessage ?? "") }
    }
}
