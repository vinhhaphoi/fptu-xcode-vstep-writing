import SwiftUI

struct ContentView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some View {
        TabBarView()
    }
}

struct TabBarView: View {
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
            Tab(role: .search) {
                NavigationStack {
                    SearchView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
