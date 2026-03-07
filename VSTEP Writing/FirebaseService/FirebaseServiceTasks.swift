import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Fetch Tasks
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
}
