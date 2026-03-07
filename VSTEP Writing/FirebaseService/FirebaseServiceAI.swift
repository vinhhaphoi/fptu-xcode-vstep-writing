internal import FirebaseFirestoreInternal
import FirebaseFunctions
import Foundation

extension FirebaseService {

    // MARK: - Ask AI
    func askAI(messages: [ChatMessage]) async throws -> String {
        guard isAuthenticated else {
            throw AIChatError.unauthenticated
        }

        let formattedMessages: [[String: Any]] = messages.map { message in
            [
                "role": message.role.rawValue,
                "content": [["text": message.content]],
            ]
        }

        let payload: [String: Any] = ["messages": formattedMessages]

        do {
            let result = try await functions.httpsCallable("askAI").call(
                payload
            )

            guard
                let data = result.data as? [String: Any],
                let reply = data["response"] as? String
            else {
                throw AIChatError.invalidResponseFormat
            }

            print("[FirebaseService] askAI reply received")
            return reply

        } catch let error as NSError {
            if let chatError = error as? AIChatError { throw chatError }

            guard error.domain == FunctionsErrorDomain else {
                throw AIChatError.unknown(error.localizedDescription)
            }

            switch FunctionsErrorCode(rawValue: error.code) {
            case .unauthenticated: throw AIChatError.unauthenticated
            case .internal, .unavailable, .deadlineExceeded:
                throw AIChatError.serverBusy
            default: throw AIChatError.unknown(error.localizedDescription)
            }
        }
    }

    // MARK: - Fetch Weekly Insight Usage
    func fetchWeeklyInsightUsage() async throws -> WeeklyInsightUsage {  // Them async
        guard let uid = currentUserId else { return .empty }

        let snap =
            try await db
            .collection("users").document(uid)
            .collection("analytics").document("insightUsage")
            .getDocument()

        guard let data = snap.data() else { return .empty }

        return WeeklyInsightUsage(
            weekKey: data["weekKey"] as? String ?? "",
            usedCount: data["usedCount"] as? Int ?? 0
        )
    }

    // MARK: - Increment Weekly Insight Refresh
    func incrementInsightRefresh(weekKey: String) async throws {  // Them async
        guard let uid = currentUserId else { return }

        let ref =
            db
            .collection("users").document(uid)
            .collection("analytics").document("insightUsage")

        try await ref.setData(
            [
                "weekKey": weekKey,
                "usedCount": FieldValue.increment(Int64(1)),
                "lastRefreshAt": FieldValue.serverTimestamp(),
            ],
            merge: true
        )
    }
}
