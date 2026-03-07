import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Daily Usage Document Key
    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func usageRef(userId: String) -> DocumentReference {
        db.collection("users").document(userId)
            .collection("dailyUsage").document(todayKey())
    }

    // MARK: - Fetch Today Usage
    func fetchTodayUsage() async throws -> DailyUsage {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let doc = try await usageRef(userId: userId).getDocument()

        guard doc.exists, let data = doc.data() else {
            return .empty
        }

        return DailyUsage(
            gradingAttemptsPerEssay: data["gradingAttemptsPerEssay"]
                as? [String: Int] ?? [:],
            totalEssaysGradedToday: data["totalEssaysGradedToday"] as? Int ?? 0,
            chatbotQuestionsToday: data["chatbotQuestionsToday"] as? Int ?? 0,
            submissionsPerEssay: data["submissionsPerEssay"] as? [String: Int]
                ?? [:]
        )
    }

    // MARK: - Increment Grading Attempt
    // Only increments totalEssaysGradedToday on first attempt for that essay
    func incrementGradingAttempt(for questionId: String) async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let ref = usageRef(userId: userId)
        let doc = try await ref.getDocument()
        let existing =
            doc.data()?["gradingAttemptsPerEssay"] as? [String: Int] ?? [:]
        let isNewEssay = existing[questionId] == nil

        var updates: [String: Any] = [
            "gradingAttemptsPerEssay.\(questionId)": FieldValue.increment(
                Int64(1)
            )
        ]

        if isNewEssay {
            updates["totalEssaysGradedToday"] = FieldValue.increment(Int64(1))
        }

        try await ref.setData(updates, merge: true)
    }

    // MARK: - Increment Chatbot Question
    func incrementChatbotQuestion() async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        try await usageRef(userId: userId).setData(
            ["chatbotQuestionsToday": FieldValue.increment(Int64(1))],
            merge: true
        )
    }

    // MARK: - Increment Submission
    func incrementSubmission(for questionId: String) async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        try await usageRef(userId: userId).setData(
            [
                "submissionsPerEssay.\(questionId)": FieldValue.increment(
                    Int64(1)
                )
            ],
            merge: true
        )
    }
}
