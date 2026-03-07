import FirebaseFirestore
import Foundation

extension FirebaseService {

    // MARK: - Create Session
    func createChatSession() async throws -> String {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let session = ChatSession(
            createdAt: Date(),
            updatedAt: Date(),
            messages: []
        )

        let ref =
            try await db
            .collection("users").document(userId)
            .collection("chatSessions")
            .addDocument(data: Firestore.Encoder().encode(session))

        print("[FirebaseService] Created chat session: \(ref.documentID)")
        return ref.documentID
    }

    // MARK: - Append Message
    func appendMessage(_ message: ChatMessage, toSession sessionId: String)
        async throws
    {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let record = ChatMessageRecord(from: message)
        let encoded = try Firestore.Encoder().encode(record)

        try await db
            .collection("users").document(userId)
            .collection("chatSessions").document(sessionId)
            .updateData([
                "messages": FieldValue.arrayUnion([encoded]),
                "updatedAt": FieldValue.serverTimestamp(),
            ])
    }

    // MARK: - Load Latest Session
    func loadLatestChatSession() async throws -> (
        sessionId: String, messages: [ChatMessage]
    )? {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let snapshot =
            try await db
            .collection("users").document(userId)
            .collection("chatSessions")
            .order(by: "updatedAt", descending: true)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else { return nil }

        let session = try doc.data(as: ChatSession.self)
        let messages = session.messages.map { $0.toChatMessage() }

        print(
            "[FirebaseService] Loaded session \(doc.documentID) with \(messages.count) messages"
        )
        return (sessionId: doc.documentID, messages: messages)
    }

    // MARK: - Fetch All Sessions
    func fetchAllChatSessions() async throws -> [ChatSession] {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        let snapshot =
            try await db
            .collection("users").document(userId)
            .collection("chatSessions")
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        return try snapshot.documents.compactMap {
            try $0.data(as: ChatSession.self)
        }
    }

    // MARK: - Delete Session
    func deleteChatSession(sessionId: String) async throws {
        guard let userId = currentUserId else {
            throw FirebaseServiceError.notAuthenticated
        }

        try await db
            .collection("users").document(userId)
            .collection("chatSessions").document(sessionId)
            .delete()

        print("[FirebaseService] Deleted chat session: \(sessionId)")
    }
}
