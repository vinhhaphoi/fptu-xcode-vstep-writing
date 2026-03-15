import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Fetch User Progress
    // Reads from users/{userId} main document, field 'stats'
    func fetchUserProgress() async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let snapshot = try await db.collection("users").document(userId)
            .getDocument()

        guard snapshot.exists,
            let data = snapshot.data(),
            let statsData = data["stats"] as? [String: Any]
        else { return }

        do {
            let sanitized = sanitizeForJSON(statsData)
            let jsonData = try JSONSerialization.data(withJSONObject: sanitized)
            let stats = try JSONDecoder().decode(UserStats.self, from: jsonData)

            self.userProgress = UserProgress(
                completedQuestions: stats.completedQuestions,
                averageScore: stats.averageScore,
                totalSubmissions: stats.totalSubmissions,
                lastActivityDate: stats.lastCalculatedAt.flatMap {
                    ISO8601DateFormatter().date(from: $0)
                },
                task1Completed: stats.task1Count,
                task2Completed: stats.task2Count
            )
        } catch {
            print("[FirebaseService] Error decoding stats: \(error)")
        }
    }

    // MARK: - Check Stats
    func isQuestionCompleted(_ questionId: String) -> Bool {
        userProgress?.completedQuestions.contains(questionId) ?? false
    }

    // MARK: - Private Helpers
    private func sanitizeForJSON(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { sanitizeForJSON($0) }
        } else if let array = value as? [Any] {
            return array.map { sanitizeForJSON($0) }
        } else if let timestamp = value as? Timestamp {
            return ISO8601DateFormatter().string(from: timestamp.dateValue())
        } else if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        return value
    }
}
