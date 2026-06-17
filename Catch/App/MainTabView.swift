import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("피드", systemImage: "square.stack.3d.up.fill") }

            HomeView()
                .environmentObject(auth)
                .tabItem { Label("수집", systemImage: "circle.grid.3x3.fill") }
        }
        .tint(.white)
    }
}
