import SwiftUI

struct ContentView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some View {
        TabBarView()
    }
}

struct TabBarView: View {
    @State private var unreadCount = 0

    var body: some View {
        TabView {
            Tab {
                NavigationStack { HomeView() }
            } label: {
                Label("Home", systemImage: "house")
                    .environment(\.symbolVariants, .none)
            }

            Tab {
                NavigationStack { LearnView() }
            } label: {
                Label("Learn", systemImage: "books.vertical")
                    .environment(\.symbolVariants, .none)
            }

            Tab {
                NavigationStack { ScoreView() }
            } label: {
                Label("Score", systemImage: "checkmark.seal.text.page")
                    .environment(\.symbolVariants, .none)
            }

            Tab {
                NavigationStack { ProfileView() }
            } label: {
                Label("Profile", systemImage: "person")
                    .environment(\.symbolVariants, .none)
            }

            Tab(role: .search) {
                NavigationStack {
                    NotificationView()
                        .onAppear {
                            Task { await refreshUnreadCount() }
                        }
                }
            } label: {
                Label("Notifications", systemImage: "bell")
                    .environment(\.symbolVariants, .none)
            }
            .badge(unreadCount > 0 ? Text("") : nil)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Updated: apply brand primary color (#16433F) to selected tab icon
        .tint(BrandColor.light)  
        .task {
            await refreshUnreadCount()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .didReceivePushNotification
            )
        ) { _ in
            Task { await refreshUnreadCount() }
        }
    }

    private func refreshUnreadCount() async {
        let all =
            (try? await NotificationService.shared.fetchNotifications()) ?? []
        unreadCount = all.filter { !$0.isRead }.count
    }
}
