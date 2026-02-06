import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Debug
        if let app = FirebaseApp.app() {
            print("✅ Firebase configured successfully")
            print("📱 Firebase app name: \(app.name)")
        }
        
        return true
    }
    
    // Handle Google Sign-In callback (nếu dùng)
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Sẽ thêm Google Sign-In handler sau
        return true
    }
}

@main
struct VSTEP_WritingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()  // ← Thay ContentView() bằng RootView()
                .environmentObject(authManager)
        }
    }
}
