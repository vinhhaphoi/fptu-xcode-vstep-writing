// FirebaseService.swift
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    
    @Published var tasks: [VSTEPTask] = []
    @Published var questions: [VSTEPQuestion] = []
    @Published var rubric: VSTEPRubric?
    @Published var userProgress: UserProgress?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    var isAuthenticated: Bool {
        currentUserId != nil
    }
    
    private init() {}
    
    // MARK: - Fetch Tasks
    func fetchTasks() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection("tasks")
            .order(by: "taskId")
            .getDocuments()
        
        tasks = try snapshot.documents.compactMap { doc in
            try doc.data(as: VSTEPTask.self)
        }
        
        print("✅ Fetched \(tasks.count) tasks")
    }
    
    // MARK: - Fetch All Questions
    func fetchQuestions() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection("questions")
            .order(by: "questionId")
            .getDocuments()
        
        questions = try snapshot.documents.compactMap { doc in
            try doc.data(as: VSTEPQuestion.self)
        }
        
        print("✅ Fetched \(questions.count) questions")
    }
    
    // MARK: - Fetch Questions by Task Type
    func fetchQuestions(taskType: String) async throws -> [VSTEPQuestion] {
        let snapshot = try await db.collection("questions")
            .whereField("taskType", isEqualTo: taskType)
            .order(by: "questionId")
            .getDocuments()
        
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: VSTEPQuestion.self)
        }
    }
    
    // MARK: - Fetch Single Question
    func fetchQuestion(questionId: String) async throws -> VSTEPQuestion? {
        let snapshot = try await db.collection("questions")
            .whereField("questionId", isEqualTo: questionId)
            .limit(to: 1)
            .getDocuments()
        
        guard let doc = snapshot.documents.first else { return nil }
        return try doc.data(as: VSTEPQuestion.self)
    }
    
    // MARK: - Fetch Rubric
    func fetchRubric() async throws {
        let snapshot = try await db.collection("rubrics")
            .document("vstep_writing_rubric")
            .getDocument()
        
        rubric = try snapshot.data(as: VSTEPRubric.self)
        print("✅ Fetched rubric")
    }
    
    // MARK: - Submit Answer
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
        
        try await db.collection("users")
            .document(userId)
            .collection("submissions")
            .addDocument(data: try Firestore.Encoder().encode(submission))
        
        // Update user progress
        try await updateUserProgress(questionId: questionId)
        
        print("✅ Submitted answer for question \(questionId)")
    }
    
    // MARK: - Fetch User Submissions
    func fetchUserSubmissions() async throws -> [UserSubmission] {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("submissions")
            .order(by: "submittedAt", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: UserSubmission.self)
        }
    }
    
    // MARK: - Fetch User Progress
    func fetchUserProgress() async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("progress")
            .document("overall")
            .getDocument()
        
        if snapshot.exists {
            userProgress = try snapshot.data(as: UserProgress.self)
        } else {
            // Create initial progress
            let initialProgress = UserProgress(
                completedQuestions: [],
                averageScore: 0.0,
                totalSubmissions: 0,
                lastActivityDate: Date(),
                task1Completed: 0,
                task2Completed: 0
            )
            
            try await db.collection("users")
                .document(userId)
                .collection("progress")
                .document("overall")
                .setData(try Firestore.Encoder().encode(initialProgress))
            
            userProgress = initialProgress
        }
    }
    
    // MARK: - Update User Progress
    private func updateUserProgress(questionId: String) async throws {
        guard let userId = currentUserId else { return }
        
        let progressRef = db.collection("users")
            .document(userId)
            .collection("progress")
            .document("overall")
        
        try await progressRef.updateData([
            "completedQuestions": FieldValue.arrayUnion([questionId]),
            "totalSubmissions": FieldValue.increment(Int64(1)),
            "lastActivityDate": FieldValue.serverTimestamp()
        ])
    }
    
    // MARK: - Check if Question is Completed
    func isQuestionCompleted(_ questionId: String) -> Bool {
        userProgress?.completedQuestions.contains(questionId) ?? false
    }
    
    // MARK: - Get Stats
    func getStats() -> (total: Int, completed: Int, task1: Int, task2: Int) {
        let total = questions.count
        let completed = userProgress?.completedQuestions.count ?? 0
        let task1 = userProgress?.task1Completed ?? 0
        let task2 = userProgress?.task2Completed ?? 0
        
        return (total, completed, task1, task2)
    }
}
