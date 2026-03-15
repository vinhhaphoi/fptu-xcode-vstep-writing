import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Submit Essay
    // Path: submissions/{userId}/submissions/{submissionId}
    func submitEssay(_ submission: UserSubmission) async throws -> String {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        var submissionWithId = submission
        submissionWithId.userId = userId

        let ref =
            try await db
            .collection("submissions")
            .document(userId)
            .collection("submissions")
            .addDocument(data: Firestore.Encoder().encode(submissionWithId))

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
            .collection("submissions")
            .document(userId)
            .collection("submissions")
            .order(by: "submittedAt", descending: true)
            .getDocuments()

        print("[FirebaseService] fetchUserSubmissions — \(snapshot.documents.count) docs fetched for user \(userId)")

        var results: [UserSubmission] = []
        for doc in snapshot.documents {
            do {
                let sub = try doc.data(as: UserSubmission.self)
                results.append(sub)
            } catch {
                print("[FirebaseService] Skipping submission \(doc.documentID): \(error.localizedDescription)")
            }
        }
        return results
    }

    // MARK: - Real-time Submissions Listener
    /// Call once (e.g. from ScoreView.task). Updates `userSubmissions` automatically.
    func listenUserSubmissions() {
        guard let userId = currentUserId else { return }
        userSubmissionsListener?.remove()

        userSubmissionsListener = db
            .collection("submissions")
            .document(userId)
            .collection("submissions")
            .order(by: "submittedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error {
                    print("[FirebaseService] userSubmissions listener error: \(error.localizedDescription)")
                    return
                }
                guard let self, let snapshot else { return }
                var results: [UserSubmission] = []
                for doc in snapshot.documents {
                    if let sub = try? doc.data(as: UserSubmission.self) {
                        results.append(sub)
                    }
                }
                self.userSubmissions = results
                print("[FirebaseService] userSubmissions updated — \(results.count) docs")
            }
    }

    func stopListeningUserSubmissions() {
        userSubmissionsListener?.remove()
        userSubmissionsListener = nil
    }

    // MARK: - Fetch Submissions for Question
    func fetchSubmissions(forQuestionId questionId: String) async throws
        -> [UserSubmission]
    {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let snapshot =
            try await db
            .collection("submissions")
            .document(userId)
            .collection("submissions")
            .whereField("questionId", isEqualTo: questionId)
            .order(by: "submittedAt", descending: true)
            .getDocuments()

        var results: [UserSubmission] = []
        for doc in snapshot.documents {
            do {
                let sub = try doc.data(as: UserSubmission.self)
                results.append(sub)
            } catch {
                print("[FirebaseService] Skipping submission \(doc.documentID): \(error.localizedDescription)")
            }
        }
        return results
    }

    // MARK: - Update Submission Score (teacher/admin only)
    // Uses collectionGroup — teacher does not need to know userId
    func updateSubmissionScore(
        submissionId: String,
        score: Double,
        feedback: String
    ) async throws {
        let query =
            try await db
            .collectionGroup("submissions")
            .whereField(FieldPath.documentID(), isEqualTo: submissionId)
            .getDocuments()

        guard let docRef = query.documents.first?.reference else {
            print("[FirebaseService] Submission not found for update")
            return
        }

        try await docRef.updateData([
            "score": score,
            "feedback": feedback,
            "status": SubmissionStatus.graded.rawValue,
            "gradedAt": FieldValue.serverTimestamp(),
        ])

        // Stats aggregation triggered automatically by Cloud Function onSubmissionUpdated
        print("[FirebaseService] Score updated for submission \(submissionId)")
    }

    // MARK: - Listen for Grading Result
    // Uses collectionGroup to locate doc, then attaches snapshot listener
    func listenForGradingResult(
        submissionId: String,
        questionId: String,
        gradingMethod: GradingMethod = .normal,
        onChange: @escaping (UserSubmission) -> Void,
        onTimeout: @escaping () -> Void
    ) {
        guard let userId = currentUserId else { return }

        stopListening(forQuestionId: questionId)

        // Direct path is faster than collectionGroup since we know userId
        let docRef =
            db
            .collection("submissions")
            .document(userId)
            .collection("submissions")
            .document(submissionId)

        let listener = docRef.addSnapshotListener { snapshot, error in
            if let error {
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

        // Only apply a timeout for AI grading (120s) and Quick grading (300s)
        // Normal queue has no timeout — a teacher may grade hours later
        let timeoutSeconds: UInt64?
        switch gradingMethod {
        case .ai:     timeoutSeconds = 120
        case .quick:  timeoutSeconds = 300
        case .normal: timeoutSeconds = nil
        }

        guard let seconds = timeoutSeconds else { return }

        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard self.submissionListeners[questionId] != nil else { return }

            print(
                "[FirebaseService] Timeout: submission \(submissionId) exceeded \(seconds)s"
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
