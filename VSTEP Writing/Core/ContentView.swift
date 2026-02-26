import SwiftUI

struct ContentView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some View {
        TabBarView()
    }
}

struct TabBarView: View {
    @State private var notificationCount = 0

    var body: some View {
        TabView {
            // Home Tab
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeView()
                }
            }

            // Learn Tab
            Tab("Learn", systemImage: "graduationcap") {
                NavigationStack {
                    LearnView()
                }
            }

            // Score Tab
            Tab("Score", systemImage: "chart.bar.xaxis.ascending") {
                NavigationStack {
                    ScoreView()
                }
            }

            // Profile Tab
            Tab("Profile", systemImage: "person") {
                NavigationStack {
                    ProfileView()
                }
            }

            // Search Tab
            Tab("Notifications", systemImage: "bell", role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
            .badge(notificationCount > 0 ? notificationCount : 0)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
