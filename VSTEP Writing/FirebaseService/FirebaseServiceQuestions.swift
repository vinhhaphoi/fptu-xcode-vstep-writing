import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Question Map (cache)
    var questionMap: [String: VSTEPQuestion] {
        Dictionary(uniqueKeysWithValues: questions.map { ($0.questionId, $0) })
    }

    // MARK: - Fetch All Questions
    func fetchQuestions() async throws {
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db.collection("questions")
            .order(by: "questionId")
            .getDocuments()

        questions = snapshot.documents.compactMap { doc in
            do {
                return try doc.data(as: VSTEPQuestion.self)
            } catch {
                print(
                    "[FirebaseService] Skip question \(doc.documentID): \(error.localizedDescription)"
                )
                return nil
            }
        }
        print("[FirebaseService] Fetched \(questions.count) questions")
    }

    // MARK: - Fetch Questions by Task Type
    func fetchQuestions(taskType: String) async throws -> [VSTEPQuestion] {
        let snapshot = try await db.collection("questions")
            .whereField("taskType", isEqualTo: taskType)
            .order(by: "questionId")
            .getDocuments()

        return try snapshot.documents.compactMap {
            try $0.data(as: VSTEPQuestion.self)
        }
    }

    // MARK: - Fetch Single Question (cache-first)
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

    // MARK: - Fetch Rubric
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
}
