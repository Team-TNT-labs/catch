import SwiftUI

/// 세션 상태에 따라 화면을 분기한다. 가입(username 설정)해야 메인 진입.
struct RootView: View {
    @StateObject private var auth = AuthService()
    @StateObject private var pro = ProStore()
    @StateObject private var locales = LocaleManager()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch auth.state {
            case .loading:
                CatchLoader()
            case .signedOut:
                SignInView().environmentObject(auth)
            case .needsUsername:
                OnboardingUsernameView().environmentObject(auth)
            case .ready:
                MainContainerView().environmentObject(auth).environmentObject(pro).environmentObject(locales)
            }
        }
        .id(locales.refresh)                       // 언어 변경 시 전체 재구성
        .environment(\.locale, locales.locale)
        .tint(Theme.coral)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: auth.state)
        .overlay {
            // 화면 전체를 테마 라임 라인으로 두름(디바이스 코너에 맞춤)
            RoundedRectangle(cornerRadius: displayCornerRadius, style: .continuous)
                .strokeBorder(Theme.lime, lineWidth: 3.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

/// 디바이스 디스플레이 코너 반경(없으면 근사값).
private var displayCornerRadius: CGFloat {
    (UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat) ?? 55
}
