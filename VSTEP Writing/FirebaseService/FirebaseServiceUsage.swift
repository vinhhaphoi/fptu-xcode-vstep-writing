import FirebaseFirestore
import Foundation

// MARK: - Firestore Map Helpers

/// Safely converts a Firestore nested map (returned as [String: Any]) to [String: Int].
private func intMapFromFirestore(_ raw: Any?) -> [String: Int] {
    guard let dict = raw as? [String: Any] else { return [:] }
    return dict.compactMapValues { ($0 as? NSNumber)?.intValue }
}

/// Extracts values from flat dot-notation keys like "submissionsPerEssay.q011"
/// into a [String: Int] map (for backwards compatibility with old data format).
private func extractFlatDotMap(from data: [String: Any], prefix: String) -> [String: Int] {
    var result: [String: Int] = [:]
    for (key, value) in data {
        if key.hasPrefix(prefix), let intVal = (value as? NSNumber)?.intValue {
            let subKey = String(key.dropFirst(prefix.count))
            if !subKey.isEmpty {
                result[subKey] = intVal
            }
        }
    }
    return result
}

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

        // Support both nested maps AND old flat dot-notation keys
        let gradingMap = intMapFromFirestore(data["gradingAttemptsPerEssay"])
            .merging(extractFlatDotMap(from: data, prefix: "gradingAttemptsPerEssay.")) { nested, _ in nested }
        let submissionMap = intMapFromFirestore(data["submissionsPerEssay"])
            .merging(extractFlatDotMap(from: data, prefix: "submissionsPerEssay.")) { nested, _ in nested }

        return DailyUsage(
            gradingAttemptsPerEssay: gradingMap,
            totalEssaysGradedToday: (data["totalEssaysGradedToday"] as? NSNumber)?.intValue ?? 0,
            chatbotQuestionsToday: (data["chatbotQuestionsToday"] as? NSNumber)?.intValue ?? 0,
            submissionsPerEssay: submissionMap
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
        let data = doc.data()

        // Read existing map (handles both nested + flat formats)
        let existing = intMapFromFirestore(data?["gradingAttemptsPerEssay"])
            .merging(extractFlatDotMap(from: data ?? [:], prefix: "gradingAttemptsPerEssay.")) { nested, _ in nested }
        let isNewEssay = existing[questionId] == nil

        // Build the updated map and write as a proper nested structure
        var gradingMap = existing
        gradingMap[questionId] = (gradingMap[questionId] ?? 0) + 1

        var updates: [String: Any] = [
            "gradingAttemptsPerEssay": gradingMap
        ]

        if isNewEssay {
            let currentTotal = (data?["totalEssaysGradedToday"] as? NSNumber)?.intValue ?? 0
            updates["totalEssaysGradedToday"] = currentTotal + 1
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

        let ref = usageRef(userId: userId)
        let doc = try await ref.getDocument()
        let data = doc.data()

        // Read existing map (handles both nested + flat formats)
        let existing = intMapFromFirestore(data?["submissionsPerEssay"])
            .merging(extractFlatDotMap(from: data ?? [:], prefix: "submissionsPerEssay.")) { nested, _ in nested }

        var submissionMap = existing
        submissionMap[questionId] = (submissionMap[questionId] ?? 0) + 1

        try await ref.setData(["submissionsPerEssay": submissionMap], merge: true)
    }
}
