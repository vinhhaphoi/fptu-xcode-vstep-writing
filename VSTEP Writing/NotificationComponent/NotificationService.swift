// NotificationService.swift

import FirebaseAuth
import FirebaseFirestore
import Foundation

// Handles saving FCM token and storing notification history in Firestore
final class NotificationService {
    static let shared = NotificationService()
    private let db = Firestore.firestore()

    private init() {}

    // Save FCM token to Firestore under current user
    func saveFCMToken(_ token: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).setData(
                ["fcmToken": token],
                merge: true
            )
        } catch {
            print(
                "[NotificationService] saveFCMToken error: \(error.localizedDescription)"
            )
        }
    }

    // Fetch notification history from Firestore
    func fetchNotifications() async throws -> [AppNotification] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snapshot =
            try await db
            .collection("users")
            .document(uid)
            .collection("notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            try? doc.data(as: AppNotification.self)
        }
    }

    // Save incoming notification to Firestore history
    // Called from AppDelegate when notification arrives (foreground or tap)
    // Called from NotificationTestHelper when scheduling local test notification
    func saveNotificationHistory(
        title: String,
        body: String,
        userInfo: [AnyHashable: Any]
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            // Most likely cause - user not logged in when test button tapped
            print(
                "[NotificationService] SKIP saveNotificationHistory: no logged-in user"
            )
            return
        }
        print("[NotificationService] Saving for uid: \(uid)")

        // Map event_type from FCM payload to AppNotification type string
        let eventType = userInfo["event_type"] as? String ?? "reminder"
        let notificationType: String
        switch eventType {
        case "essay_graded":
            notificationType = "graded"
        case "new_assignment", "new_blog":
            notificationType = "new_question"
        default:
            notificationType = "reminder"
        }

        // Extract relatedId based on event type
        let relatedId: String?
        switch eventType {
        case "essay_graded":
            relatedId = userInfo["essay_id"] as? String
        case "new_assignment":
            relatedId = userInfo["assignment_id"] as? String
        case "new_blog":
            relatedId = userInfo["blog_id"] as? String
        default:
            relatedId = nil
        }

        let data: [String: Any] = [
            "title": title,
            "body": body,
            "type": notificationType,
            "relatedId": relatedId as Any,
            "isRead": false,
            "createdAt": FieldValue.serverTimestamp(),
        ]

        do {
            try await db
                .collection("users")
                .document(uid)
                .collection("notifications")
                .addDocument(data: data)
            print("[NotificationService] Saved notification: \(title)")
        } catch {
            print(
                "[NotificationService] saveNotificationHistory error: \(error.localizedDescription)"
            )
        }
    }

    // Mark notification as read
    func markAsRead(_ notificationId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db
                .collection("users")
                .document(uid)
                .collection("notifications")
                .document(notificationId)
                .updateData(["isRead": true])
        } catch {
            print(
                "[NotificationService] markAsRead error: \(error.localizedDescription)"
            )
        }
    }

    func deleteAllNotifications() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot =
                try await db
                .collection("users")
                .document(uid)
                .collection("notifications")
                .getDocuments()

            // Delete all documents in parallel
            try await withThrowingTaskGroup(of: Void.self) { group in
                for doc in snapshot.documents {
                    group.addTask {
                        try await doc.reference.delete()
                    }
                }
                try await group.waitForAll()
            }
            print("[NotificationService] Deleted all notifications")
        } catch {
            print(
                "[NotificationService] deleteAllNotifications error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - AppNotification Model
struct AppNotification: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let body: String
    let type: String
    let relatedId: String?
    var isRead: Bool
    let createdAt: Date

    var notificationType: NotificationType {
        switch type {
        case "graded": return .graded
        case "new_question": return .newQuestion
        default: return .reminder
        }
    }

    enum NotificationType {
        case graded, newQuestion, reminder

        var icon: String {
            switch self {
            case .graded: return "checkmark.seal.fill"
            case .newQuestion: return "doc.badge.plus"
            case .reminder: return "flame.fill"
            }
        }

        var color: String {
            switch self {
            case .graded: return "green"
            case .newQuestion: return "blue"
            case .reminder: return "orange"
            }
        }
    }
}
