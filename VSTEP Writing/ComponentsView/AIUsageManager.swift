import Foundation
import Observation
import FirebaseAuth
import FirebaseFunctions
internal import FirebaseFirestoreInternal

// MARK: - GradingResult
// Response model for manualGradeSubmission
struct GradingResult {
    let score: Double
    let overallComment: String
    let criteria: [[String: Any]]
    let suggestions: [String]
}

// MARK: - AIUsageManager
@Observable
class AIUsageManager {
    static let shared = AIUsageManager()

    // MARK: - State
    var subscriptionTier: String = "free"
    var isSubscribed: Bool = false
    var isLoading: Bool = false

    private var functions: Functions

    private init() {
        self.functions = Functions.functions(region: "asia-southeast1")
    }

    // MARK: - Load Subscription Status from Firestore
    func loadSubscriptionStatus() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("[AIUsageManager] No authenticated user")
            return
        }

        await MainActor.run { isLoading = true }

        do {
            let userDoc = try await FirebaseService.shared.db
                .collection("users")
                .document(userId)
                .getDocument()

            await MainActor.run {
                self.subscriptionTier = userDoc.data()?["subscriptionTier"] as? String ?? "free"
                self.isSubscribed = userDoc.data()?["isSubscribed"] as? Bool ?? false
                self.isLoading = false
                print("[AIUsageManager] Tier: \(subscriptionTier), subscribed: \(isSubscribed)")
            }
        } catch {
            await MainActor.run { self.isLoading = false }
            print("[AIUsageManager] Load subscription error: \(error.localizedDescription)")
        }
    }

    // MARK: - manualGradeSubmission
    // Request:  { targetUserId: String, submissionId: String }
    // Response: { success: Bool, result: { score, overallComment, criteria, suggestions } }
    func requestManualGrading(
        submissionId: String,
        targetUserId: String? = nil
    ) async throws -> GradingResult {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw AIUsageError.unauthenticated(message: "Please login to use AI features.")
        }

        let data: [String: Any] = [
            "targetUserId": targetUserId ?? currentUserId,
            "submissionId": submissionId
        ]

        do {
            let result = try await functions.httpsCallable("manualGradeSubmission").call(data)

            guard
                let response = result.data as? [String: Any],
                let success = response["success"] as? Bool, success,
                let resultMap = response["result"] as? [String: Any]
            else {
                throw AIUsageError.invalidResponse
            }

            print("[AIUsageManager] Grading requested for: \(submissionId)")

            return GradingResult(
                score: resultMap["score"] as? Double ?? 0,
                overallComment: resultMap["overallComment"] as? String ?? "",
                criteria: resultMap["criteria"] as? [[String: Any]] ?? [],
                suggestions: resultMap["suggestions"] as? [String] ?? []
            )

        } catch let error as NSError {
            throw mapFunctionError(error)
        }
    }

    // MARK: - askAI
    // Request:  { prompt: String, messages: [{ role, content }], questionId? (optional), systemPrompt? (optional) }
    // Response: { response: String }
    // Uses existing ChatMessage model with MessageRole enum from Models.swift
    func askAI(
        prompt: String,
        messages: [ChatMessage] = [],
        questionId: String? = nil,
        systemPrompt: String? = nil
    ) async throws -> String {
        guard Auth.auth().currentUser != nil else {
            throw AIUsageError.unauthenticated(message: "Please login to use AI features.")
        }

        var data: [String: Any] = [
            "prompt": prompt,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]

        if let questionId {
            data["questionId"] = questionId
        }

        if let systemPrompt {
            data["systemPrompt"] = systemPrompt
        }

        do {
            let result = try await functions.httpsCallable("askAI").call(data)

            guard
                let response = result.data as? [String: Any],
                let text = response["response"] as? String
            else {
                throw AIUsageError.invalidResponse
            }

            print("[AIUsageManager] askAI response received")
            return text

        } catch let error as NSError {
            throw mapFunctionError(error)
        }
    }

    // MARK: - analyzeUserProgress
    // Request:  { targetLevel: String, forceRefresh: Bool }
    // Response: { insights: UserProgressInsights, cached: Bool, updatedAt: String?, usedCount?, weeklyLimit?, weekKey? }
    // Uses existing AnalyzeProgressResponse + UserProgressInsights from Models.swift
    func analyzeUserProgress(
        targetLevel: String = "B1",
        forceRefresh: Bool = false
    ) async throws -> AnalyzeProgressResponse {
        guard Auth.auth().currentUser != nil else {
            throw AIUsageError.unauthenticated(message: "Please login to use AI features.")
        }

        let data: [String: Any] = [
            "targetLevel": targetLevel,
            "forceRefresh": forceRefresh
        ]

        do {
            let result = try await functions.httpsCallable("analyzeUserProgress").call(data)

            guard let rawData = result.data as? [String: Any] else {
                throw AIUsageError.invalidResponse
            }

            // Decode via JSONSerialization -> Codable
            let jsonData = try JSONSerialization.data(withJSONObject: rawData)
            let response = try JSONDecoder().decode(AnalyzeProgressResponse.self, from: jsonData)

            print("[AIUsageManager] analyzeUserProgress received (cached: \(response.cached))")
            return response

        } catch let error as NSError {
            throw mapFunctionError(error)
        }
    }

    // MARK: - verifyStoreKitPurchase (Buy / Restore)
    // Request:  { transactionId: String, productId: String }
    // Response: { success: Bool, tier: String, expiryDate: String }
    func verifyStoreKitPurchase(
        transactionId: UInt64,
        productId: String
    ) async throws {
        let data: [String: Any] = [
            "transactionId": String(transactionId),
            "productId": productId
        ]

        do {
            let result = try await functions.httpsCallable("verifyStoreKitPurchase").call(data)

            guard
                let response = result.data as? [String: Any],
                let success = response["success"] as? Bool, success
            else {
                throw AIUsageError.invalidResponse
            }

            let tier = response["tier"] as? String ?? "free"
            let expiryDate = response["expiryDate"] as? String ?? ""
            print("[AIUsageManager] StoreKit verified — tier: \(tier), expiry: \(expiryDate)")

            await loadSubscriptionStatus()

        } catch let error as NSError {
            throw mapFunctionError(error)
        }
    }

    // MARK: - revokeSubscription (Refund)
    // Request:  { clearStatus: true }
    // Response: { success: Bool }
    func revokeSubscription() async throws {
        let data: [String: Any] = ["clearStatus": true]

        do {
            let result = try await functions.httpsCallable("verifyStoreKitPurchase").call(data)

            guard
                let response = result.data as? [String: Any],
                let success = response["success"] as? Bool, success
            else {
                throw AIUsageError.invalidResponse
            }

            print("[AIUsageManager] Subscription revoked (refund)")
            await loadSubscriptionStatus()

        } catch let error as NSError {
            throw mapFunctionError(error)
        }
    }

    // MARK: - UI Helper
    func canAccessAIFeatures() -> (allowed: Bool, reason: String?) {
        guard isSubscribed else {
            return (false, "You need an active subscription to use AI features.")
        }
        guard subscriptionTier == "advanced" || subscriptionTier == "premier" else {
            return (false, "Contact admin to assign a plan.")
        }
        return (true, nil)
    }

    var tierDisplayName: String {
        switch subscriptionTier.lowercased() {
        case "advanced": return "Advanced"
        case "premier":  return "Premier"
        default:         return "Free"
        }
    }

    // MARK: - Private: Map Firebase Function Errors
    private func mapFunctionError(_ error: NSError) -> AIUsageError {
        let code = FunctionsErrorCode(rawValue: error.code)
        let message = error.userInfo["message"] as? String

        switch code {
        case .permissionDenied:
            return .permissionDenied(message: message ?? "Contact admin to assign a plan.")
        case .failedPrecondition:
            return .failedPrecondition(message: message ?? "Your subscription has expired.")
        case .resourceExhausted:
            return .resourceExhausted(message: message ?? "Daily limit reached. Upgrade for more.")
        case .unauthenticated:
            return .unauthenticated(message: message ?? "Please login to use AI features.")
        case .invalidArgument:
            return .invalidArgument(message: message ?? "Invalid request parameters.")
        default:
            print("[AIUsageManager] Unknown error: \(error.localizedDescription)")
            return .unknown(message: error.localizedDescription)
        }
    }
}
