import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation
import UIKit

// MARK: - FirebaseService
@MainActor
class FirebaseService: ObservableObject {

    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: Published State
    @Published var tasks: [VSTEPTask] = []
    @Published var questions: [VSTEPQuestion] = []
    @Published var rubric: VSTEPRubric?
    @Published var userProgress: UserProgress?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Avatar Published State
    @Published var uploadedAvatarURL: String?
    @Published var isUploadingPhoto = false
    @Published var avatarUploadError: String?

    // MARK: Auth Helpers
    var currentUserId: String? { Auth.auth().currentUser?.uid }
    var isAuthenticated: Bool { currentUserId != nil }

    // MARK: - Question Map
    var questionMap: [String: VSTEPQuestion] {
        Dictionary(uniqueKeysWithValues: questions.map { ($0.questionId, $0) })
    }

    // MARK: - Active submission listeners
    private var submissionListeners: [String: ListenerRegistration] = [:]

    private init() {}

    // ─────────────────────────────────────────────
    // MARK: - Fetch Tasks
    // ─────────────────────────────────────────────
    func fetchTasks() async throws {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("tasks")
            .order(by: "taskId")
            .getDocuments()

        tasks = try snapshot.documents.compactMap {
            try $0.data(as: VSTEPTask.self)
        }
        print("[FirebaseService] Fetched \(tasks.count) tasks")
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch All Questions
    // ─────────────────────────────────────────────
    func fetchQuestions() async throws {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("questions")
            .order(by: "questionId")
            .getDocuments()

        questions = try snapshot.documents.compactMap {
            try $0.data(as: VSTEPQuestion.self)
        }
        print("[FirebaseService] Fetched \(questions.count) questions")
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch Questions by Task Type
    // ─────────────────────────────────────────────
    func fetchQuestions(taskType: String) async throws -> [VSTEPQuestion] {
        let snapshot = try await db.collection("questions")
            .whereField("taskType", isEqualTo: taskType)
            .order(by: "questionId")
            .getDocuments()

        return try snapshot.documents.compactMap {
            try $0.data(as: VSTEPQuestion.self)
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch Single Question (cache-first)
    // ─────────────────────────────────────────────
    func fetchQuestion(questionId: String) async throws -> VSTEPQuestion? {
        if let cached = questionMap[questionId] { return cached }

        let snapshot = try await db.collection("questions")
            .whereField("questionId", isEqualTo: questionId)
            .limit(to: 1)
            .getDocuments()

        return try snapshot.documents.first.map {
            try $0.data(as: VSTEPQuestion.self)
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch Rubric
    // ─────────────────────────────────────────────
    func fetchRubric() async throws {
        let snapshot = try await db.collection("rubrics")
            .document("vstep_writing_rubric")
            .getDocument()

        guard snapshot.exists else {
            throw FirebaseServiceError.documentNotFound
        }
        rubric = try snapshot.data(as: VSTEPRubric.self)
        print("[FirebaseService] Fetched rubric")
    }

    // ─────────────────────────────────────────────
    // MARK: - Submit Answer
    // ─────────────────────────────────────────────
    func submitAnswer(
        questionId: String,
        content: String,
        wordCount: Int
    ) async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let submission = UserSubmission(
            questionId: questionId,
            content: content,
            wordCount: wordCount,
            submittedAt: Date(),
            score: nil,
            feedback: nil,
            status: .submitted
        )

        try await db
            .collection("users").document(userId)
            .collection("submissions")
            .addDocument(data: Firestore.Encoder().encode(submission))

        try await updateUserProgress(questionId: questionId)
        print("[FirebaseService] Submitted answer for \(questionId)")
    }

    // ─────────────────────────────────────────────
    // MARK: - Submit Essay (called from LearnView)
    // ─────────────────────────────────────────────
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
        print(
            "[FirebaseService] submitEssay — questionId: \(submission.questionId), docId: \(ref.documentID)"
        )
        return ref.documentID
    }

    // ─────────────────────────────────────────────
    // MARK: - Listen for AI Grading Result (real-time)
    // Auto timeout after 120 seconds if AI does not return result
    // ─────────────────────────────────────────────
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
                    "[FirebaseService] Decode submission failed: \(error.localizedDescription)"
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

    // ─────────────────────────────────────────────
    // MARK: - Stop Listeners
    // ─────────────────────────────────────────────
    func stopListening(forQuestionId questionId: String) {
        submissionListeners[questionId]?.remove()
        submissionListeners.removeValue(forKey: questionId)
    }

    func stopAllListeners() {
        submissionListeners.values.forEach { $0.remove() }
        submissionListeners.removeAll()
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch User Submissions
    // ─────────────────────────────────────────────
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

    // ─────────────────────────────────────────────
    // MARK: - Update Submission Score (after AI grading)
    // ─────────────────────────────────────────────
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

    // ─────────────────────────────────────────────
    // MARK: - Fetch User Progress
    // ─────────────────────────────────────────────
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

    // ─────────────────────────────────────────────
    // MARK: - Check / Stats
    // ─────────────────────────────────────────────
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

    // ─────────────────────────────────────────────
    // MARK: - Fetch Plan (IAP)
    // ─────────────────────────────────────────────
    func fetchPlan(productID: String) async -> Plan? {
        let doc = try? await db.collection("plans").document(productID)
            .getDocument()
        return try? doc?.data(as: Plan.self)
    }

    // ─────────────────────────────────────────────
    // MARK: - Avatar — Upload to Firebase Storage
    // Storage path: avatars/{uid}/avatar.jpg
    // ─────────────────────────────────────────────
    func uploadAvatar(
        image: UIImage,
        maxSizeInPixels: CGFloat = 512,
        compressionQuality: CGFloat = 0.7
    ) async throws -> String {
        guard let uid = currentUserId else {
            throw AvatarUploadError.noCurrentUser
        }

        // Downscale before compress to keep file size small
        let resized = resizeImage(image, maxDimension: maxSizeInPixels)

        guard
            let imageData = resized.jpegData(
                compressionQuality: compressionQuality
            )
        else {
            throw AvatarUploadError.imageCompressionFailed
        }

        let sizeKB = Double(imageData.count) / 1024
        print(
            "[FirebaseService] Avatar size after resize+compress: \(String(format: "%.1f", sizeKB)) KB"
        )

        let storageRef = storage.reference().child("avatars/\(uid)/avatar.jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        } catch {
            throw AvatarUploadError.uploadFailed(error)
        }

        let downloadURL: URL
        do {
            downloadURL = try await storageRef.downloadURL()
        } catch {
            throw AvatarUploadError.downloadURLFailed(error)
        }

        let urlString = downloadURL.absoluteString

        do {
            try await db
                .collection("users")
                .document(uid)
                .updateData(["photoURL": urlString])
        } catch {
            throw AvatarUploadError.firestoreUpdateFailed(error)
        }

        uploadedAvatarURL = urlString
        return urlString
    }

    // ─────────────────────────────────────────────
    // MARK: - Avatar — Resize image to max dimension
    // Keeps aspect ratio, only downscales (never upscales)
    // ─────────────────────────────────────────────
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage
    {
        let originalSize = image.size
        let maxSide = max(originalSize.width, originalSize.height)

        // Skip resize if already smaller than maxDimension
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(
            width: (originalSize.width * scale).rounded(),
            height: (originalSize.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Avatar — Delete from Firebase Storage
    // ─────────────────────────────────────────────
    func deleteAvatar() async throws {
        guard let uid = currentUserId else {
            throw AvatarUploadError.noCurrentUser
        }

        let storageRef = storage.reference().child("avatars/\(uid)/avatar.jpg")
        try await storageRef.delete()
        uploadedAvatarURL = nil
        print("[FirebaseService] Avatar deleted for uid: \(uid)")
    }

    // ─────────────────────────────────────────────
    // MARK: - Private Helpers
    // ─────────────────────────────────────────────
    private func progressRef(userId: String) -> DocumentReference {
        db.collection("users").document(userId)
            .collection("progress").document("overall")
    }

    private func updateUserProgress(questionId: String) async throws {
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

    private func recalculateAverageScore(userId: String) async throws {
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

    func fetchAvatarURL() async {
        guard let uid = currentUserId else { return }

        let doc = try? await db.collection("users").document(uid).getDocument()
        if let urlString = doc?.data()?["photoURL"] as? String {
            uploadedAvatarURL = urlString
        }
    }
}
