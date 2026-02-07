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
                        .navigationTitle("Home")
                        .navigationBarTitleDisplayMode(.large)
                }
            }

            // Learn Tab
            Tab("Learn", systemImage: "graduationcap") {
                NavigationStack {
                    LearnView()
                        .navigationTitle("Learn")
                        .navigationBarTitleDisplayMode(.large)
                }
            }

            // Score Tab
            Tab("Score", systemImage: "person.crop.square") {
                NavigationStack {
                    ScoreView()
                        .navigationTitle("Score")
                        .navigationBarTitleDisplayMode(.large)
                }
            }

            // Profile Tab
            Tab("Profile", systemImage: "person") {
                NavigationStack {
                    ProfileView()
                        .navigationTitle("Profile")
                        .navigationBarTitleDisplayMode(.large)
                }
            }

            // Search Tab - Special role
            Tab(role: .search) {
                NavigationStack {
                    SearchView()
                        .navigationTitle("Search")
                        .toolbarTitleDisplayMode(.inlineLarge)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
