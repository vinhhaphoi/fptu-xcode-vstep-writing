import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - FirebaseService
@MainActor
class FirebaseService: ObservableObject {

    static let shared = FirebaseService()
    private let db = Firestore.firestore()

    // MARK: Published State
    @Published var tasks: [VSTEPTask] = []
    @Published var questions: [VSTEPQuestion] = []
    @Published var rubric: VSTEPRubric?
    @Published var userProgress: UserProgress?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: Auth Helpers
    var currentUserId: String? { Auth.auth().currentUser?.uid }
    var isAuthenticated: Bool  { currentUserId != nil }

    // MARK: - Question Map
    /// Tra cứu O(1): questionId field → VSTEPQuestion
    /// FIX: questionId là String (non-optional) → dùng map thay vì compactMap+guard let
    var questionMap: [String: VSTEPQuestion] {
        Dictionary(uniqueKeysWithValues: questions.map { ($0.questionId, $0) })
    }

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
        // 1. In-memory cache
        if let cached = questionMap[questionId] { return cached }

        // 2. Fallback: Firestore query
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

        guard snapshot.exists else { throw FirebaseServiceError.documentNotFound }
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
            .addDocument(data: try Firestore.Encoder().encode(submission))

        try await updateUserProgress(questionId: questionId)
        print("[FirebaseService] Submitted answer for \(questionId)")
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch User Submissions
    // ─────────────────────────────────────────────
    func fetchUserSubmissions() async throws -> [UserSubmission] {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let snapshot = try await db
            .collection("users").document(userId)
            .collection("submissions")
            .order(by: "submittedAt", descending: true)
            .getDocuments()

        return try snapshot.documents.compactMap {
            try $0.data(as: UserSubmission.self)
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Update Submission Score (sau AI grading)
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
                "score":    score,
                "feedback": feedback,
                "status":   SubmissionStatus.graded.rawValue
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
            total:     questions.count,
            completed: userProgress?.completedQuestions.count ?? 0,
            task1:     userProgress?.task1Completed ?? 0,
            task2:     userProgress?.task2Completed ?? 0
        )
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch Plan (IAP)
    // ─────────────────────────────────────────────
    func fetchPlan(productID: String) async -> Plan? {
        let doc = try? await db.collection("plans").document(productID).getDocument()
        return try? doc?.data(as: Plan.self)
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
        try await progressRef(userId: userId).setData([
            "completedQuestions": FieldValue.arrayUnion([questionId]),
            "totalSubmissions":   FieldValue.increment(Int64(1)),
            "lastActivityDate":   FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func recalculateAverageScore(userId: String) async throws {
        let snapshot = try await db
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
