// VSTEP_WritingApp.swift

import FirebaseAppCheck
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn
import SwiftUI
import UserNotifications

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure AppCheck BEFORE FirebaseApp.configure()
        // DEBUG: Use debug provider to bypass AppCheck validation on simulator/dev device
        #if DEBUG
            let providerFactory = AppCheckDebugProviderFactory()
            AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif

        FirebaseApp.configure()

        if let app = FirebaseApp.app() {
            print("[Firebase] Configured successfully - App name: \(app.name)")
        }

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                print(
                    "[Notification] Permission error: \(error.localizedDescription)"
                )
                return
            }
            guard granted else {
                print("[Notification] Permission denied by user")
                return
            }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }

        return true
    }

    // Register APNs token with Firebase
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        print("[APNs] Token registered with Firebase")
    }

    // Handle APNs registration failure
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if targetEnvironment(simulator)
            print(
                "[APNs] Simulator detected - APNs registration skipped (expected)"
            )
        #else
            print("[APNs] Failed to register: \(error.localizedDescription)")
        #endif
    }

    // Google Sign In URL handler
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Called when notification arrives while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        // Only handle real FCM push - local test notifications are handled by NotificationTestHelper
        let isFCMPush =
            notification.request.trigger is UNPushNotificationTrigger

        print(
            "[Notification] Foreground received (FCM: \(isFCMPush)): \(content.userInfo)"
        )

        if isFCMPush {
            // Save FCM push to Firestore history
            Task {
                await NotificationService.shared.saveNotificationHistory(
                    title: content.title,
                    body: content.body,
                    userInfo: content.userInfo
                )
            }
            // Notify NotificationView to refresh list
            NotificationCenter.default.post(
                name: .didReceivePushNotification,
                object: nil,
                userInfo: content.userInfo
            )
        }

        completionHandler([.banner, .badge, .sound])
    }

    // Called when user taps a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        // Only handle real FCM push tapped from background or quit state
        // Foreground FCM push is already saved in willPresent above
        // Local test notifications are already saved in NotificationTestHelper
        let isFCMPush =
            response.notification.request.trigger is UNPushNotificationTrigger

        print(
            "[Notification] User tapped (FCM: \(isFCMPush)): \(content.userInfo)"
        )

        if isFCMPush {
            Task {
                await NotificationService.shared.saveNotificationHistory(
                    title: content.title,
                    body: content.body,
                    userInfo: content.userInfo
                )
            }
            NotificationCenter.default.post(
                name: .didReceivePushNotification,
                object: nil,
                userInfo: content.userInfo
            )
        }

        completionHandler()
    }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let token = fcmToken else { return }
        print("[FCM] Token: \(token)")
        Task {
            await NotificationService.shared.saveFCMToken(token)
        }
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let didReceivePushNotification = Notification.Name(
        "didReceivePushNotification"
    )
    // New: fired when local test notification is saved to trigger badge update
    static let didSaveLocalNotification = Notification.Name(
        "didSaveLocalNotification"
    )
}

// MARK: - VSTEP_WritingApp
@main
struct VSTEP_WritingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var firebaseService = FirebaseService.shared
    // Single shared instance for entire app lifetime
    @State private var store = StoreKitManager()

    init() {
        // Must activate on init, not onAppear
        SessionManager.shared.activateSession()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(firebaseService)
                .environment(store)
                .task {
                    await AIUsageManager.shared.loadInitialData()
                }
                .onOpenURL { url in
                    // Google Sign In callback - fallback for SwiftUI lifecycle
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
