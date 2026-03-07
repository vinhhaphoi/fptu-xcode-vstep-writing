import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Fetch User Progress
    func fetchUserProgress() async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let ref = progressRef(userId: userId)
        let snapshot = try await ref.getDocument()

        if snapshot.exists {
            userProgress = try snapshot.data(as: UserProgress.self)
        } else {
            let initial = UserProgress(
                completedQuestions: [],
                averageScore: 0.0,
                totalSubmissions: 0,
                lastActivityDate: nil,
                task1Completed: 0,
                task2Completed: 0
            )
            try await ref.setData(try Firestore.Encoder().encode(initial))
            userProgress = initial
        }
    }

    // MARK: - Check / Stats
    func isQuestionCompleted(_ questionId: String) -> Bool {
        userProgress?.completedQuestions.contains(questionId) ?? false
    }

    func getStats() -> (total: Int, completed: Int, task1: Int, task2: Int) {
        (
            total: questions.count,
            completed: userProgress?.completedQuestions.count ?? 0,
            task1: userProgress?.task1Completed ?? 0,
            task2: userProgress?.task2Completed ?? 0
        )
    }

    // MARK: - Internal Helpers
    func progressRef(userId: String) -> DocumentReference {
        db.collection("users").document(userId)
            .collection("progress").document("overall")
    }

    func updateUserProgress(questionId: String) async throws {
        guard let userId = currentUserId else { return }
        try await progressRef(userId: userId).setData(
            [
                "completedQuestions": FieldValue.arrayUnion([questionId]),
                "totalSubmissions": FieldValue.increment(Int64(1)),
                "lastActivityDate": FieldValue.serverTimestamp(),
            ],
            merge: true
        )
    }

    func recalculateAverageScore(userId: String) async throws {
        let snapshot =
            try await db
            .collection("users").document(userId)
            .collection("submissions")
            .whereField("score", isGreaterThan: 0)
            .getDocuments()

        let scores: [Double] = try snapshot.documents.compactMap {
            try $0.data(as: UserSubmission.self).score
        }
        guard !scores.isEmpty else { return }

        let average = scores.reduce(0, +) / Double(scores.count)
        try await progressRef(userId: userId)
            .setData(["averageScore": average], merge: true)
        userProgress?.averageScore = average
    }
}
