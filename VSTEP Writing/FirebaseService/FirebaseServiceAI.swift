import FirebaseFirestore
import FirebaseFunctions
import Foundation

extension FirebaseService {

    // MARK: - Ask AI
    // Request:  { prompt, messages: [{ role, content }], questionId? (optional), systemPrompt? (optional) }
    // Response: { response: String }
    func askAI(
        prompt: String,
        messages: [ChatMessage] = [],
        questionId: String? = nil,
        systemPrompt: String? = nil
    ) async throws -> String {
        guard isAuthenticated else {
            throw AIChatError.unauthenticated
        }

        // Map ChatMessage -> [role: String, content: String] per Cloud Functions v3.0
        let formattedMessages: [[String: Any]] = messages.map { message in
            [
                "role": message.role.rawValue,
                "content": message.content,
            ]
        }

        var payload: [String: Any] = [
            "prompt": prompt,
            "messages": formattedMessages,
        ]

        if let questionId {
            payload["questionId"] = questionId
        }

        if let systemPrompt {
            payload["systemPrompt"] = systemPrompt
        }

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
            case .unauthenticated:
                throw AIChatError.unauthenticated
            case .resourceExhausted:
                throw AIChatError.unknown(
                    "Daily limit reached. Upgrade for more."
                )
            case .failedPrecondition:
                throw AIChatError.unknown("Your subscription has expired.")
            case .permissionDenied:
                throw AIChatError.unknown("Contact admin to assign a plan.")
            case .internal, .unavailable, .deadlineExceeded:
                throw AIChatError.serverBusy
            default:
                throw AIChatError.unknown(error.localizedDescription)
            }
        }
    }

    // MARK: - Fetch Weekly Insight Usage
    // Deprecated: Quota is now managed server-side via analyzeUserProgress Cloud Function.
    // Kept for backward compatibility only.
    @available(
        *,
        deprecated,
        message: "Use AIUsageManager.analyzeUserProgress() instead."
    )
    func fetchWeeklyInsightUsage() async throws -> WeeklyInsightUsage {
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
    // Deprecated: Quota is now managed server-side via analyzeUserProgress Cloud Function.
    // Kept for backward compatibility only.
    @available(
        *,
        deprecated,
        message: "Use AIUsageManager.analyzeUserProgress() instead."
    )
    func incrementInsightRefresh(weekKey: String) async throws {
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
