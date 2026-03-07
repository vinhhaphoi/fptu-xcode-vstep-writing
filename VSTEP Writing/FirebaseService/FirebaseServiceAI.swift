import FirebaseFunctions
import Foundation

extension FirebaseService {

    // MARK: - Ask AI
    // Genkit-compatible mapping handled here, not in ChatMessage model
    func askAI(messages: [ChatMessage]) async throws -> String {
        guard isAuthenticated else {
            throw AIChatError.unauthenticated
        }

        let formattedMessages: [[String: Any]] = messages.map { message in
            [
                "role": message.role.rawValue,
                "content": [["text": message.content]],
            ]
        }

        let payload: [String: Any] = ["messages": formattedMessages]

        do {
            let result = try await functions.httpsCallable("askAI").call(
                payload
            )

            guard
                let data = result.data as? [String: Any],
                let reply = data["response"] as? String
            else {
                throw AIChatError.invalidResponseFormat
            }

            print("[FirebaseService] askAI reply received")
            return reply

        } catch let error as NSError {
            if let chatError = error as? AIChatError { throw chatError }

            guard error.domain == FunctionsErrorDomain else {
                throw AIChatError.unknown(error.localizedDescription)
            }

            switch FunctionsErrorCode(rawValue: error.code) {
            case .unauthenticated: throw AIChatError.unauthenticated
            case .internal, .unavailable, .deadlineExceeded:
                throw AIChatError.serverBusy
            default: throw AIChatError.unknown(error.localizedDescription)
            }
        }
    }
}
