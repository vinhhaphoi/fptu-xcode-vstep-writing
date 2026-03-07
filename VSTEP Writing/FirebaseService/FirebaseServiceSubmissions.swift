import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Submit Essay
    func submitEssay(_ submission: UserSubmission) async throws -> String {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let ref =
            try await db
            .collection("users").document(userId)
            .collection("submissions")
            .addDocument(data: Firestore.Encoder().encode(submission))

        try await updateUserProgress(questionId: submission.questionId)
        print("[FirebaseService] submitEssay — docId: \(ref.documentID)")
        return ref.documentID
    }

    // MARK: - Fetch User Submissions
    func fetchUserSubmissions() async throws -> [UserSubmission] {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let snapshot =
            try await db
            .collection("users").document(userId)
            .collection("submissions")
            .order(by: "submittedAt", descending: true)
            .getDocuments()

        return try snapshot.documents.compactMap {
            try $0.data(as: UserSubmission.self)
        }
    }

    // MARK: - Update Submission Score
    func updateSubmissionScore(
        submissionId: String,
        score: Double,
        feedback: String
    ) async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        try await db
            .collection("users").document(userId)
            .collection("submissions").document(submissionId)
            .updateData([
                "score": score,
                "feedback": feedback,
                "status": SubmissionStatus.graded.rawValue,
            ])

        try await recalculateAverageScore(userId: userId)
        print("[FirebaseService] Score updated for submission \(submissionId)")
    }

    // MARK: - Listen for AI Grading Result
    // Auto timeout after 120 seconds if AI does not return result
    func listenForGradingResult(
        submissionId: String,
        questionId: String,
        onChange: @escaping (UserSubmission) -> Void,
        onTimeout: @escaping () -> Void
    ) {
        guard let userId = currentUserId else { return }

        stopListening(forQuestionId: questionId)

        let docRef =
            db
            .collection("users").document(userId)
            .collection("submissions").document(submissionId)

        let listener = docRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print(
                    "[FirebaseService] Listener error: \(error.localizedDescription)"
                )
                return
            }
            guard let snapshot, snapshot.exists else { return }

            do {
                let updated = try snapshot.data(as: UserSubmission.self)
                print(
                    "[FirebaseService] Submission \(submissionId) status: \(updated.status.rawValue)"
                )
                onChange(updated)

                if updated.status == .graded || updated.status == .failed {
                    self.stopListening(forQuestionId: questionId)
                }
            } catch {
                print(
                    "[FirebaseService] Decode failed: \(error.localizedDescription)"
                )
            }
        }

        submissionListeners[questionId] = listener

        Task {
            try? await Task.sleep(for: .seconds(120))
            guard self.submissionListeners[questionId] != nil else { return }

            print(
                "[FirebaseService] Timeout: submission \(submissionId) exceeded 120s"
            )
            self.stopListening(forQuestionId: questionId)

            try? await docRef.updateData([
                "status": SubmissionStatus.failed.rawValue,
                "errorMessage": "AI grading timed out. Please try again.",
            ])
            onTimeout()
        }
    }

    // MARK: - Stop Listeners
    func stopListening(forQuestionId questionId: String) {
        submissionListeners[questionId]?.remove()
        submissionListeners.removeValue(forKey: questionId)
    }

    func stopAllListeners() {
        submissionListeners.values.forEach { $0.remove() }
        submissionListeners.removeAll()
    }
}
