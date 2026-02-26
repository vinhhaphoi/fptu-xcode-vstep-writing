import SwiftUI
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Debug
        if let app = FirebaseApp.app() {
            print("Firebase configured successfully")
            print("Firebase app name: \(app.name)")
        }
        
        return true
    }
}

@main
struct VSTEP_WritingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    // ← Google Sign In callback
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
