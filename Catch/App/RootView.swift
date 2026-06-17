import SwiftUI

/// 세션 상태에 따라 화면을 분기한다. 가입(username 설정)해야 메인 진입.
struct RootView: View {
    @StateObject private var auth = AuthService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch auth.state {
            case .loading:
                ProgressView().tint(.white)
            case .signedOut:
                SignInView().environmentObject(auth)
            case .needsUsername:
                OnboardingUsernameView().environmentObject(auth)
            case .ready:
                HomeView().environmentObject(auth)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.state)
    }
}
