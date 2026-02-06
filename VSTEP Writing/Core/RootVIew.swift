import SwiftUI

struct RootView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .loading:
                ProgressView("Loading ...")
            case .authenticated:
                ContentView() // ← ContentView bạn đã có
            case .unauthenticated:
                LoginView()
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}
