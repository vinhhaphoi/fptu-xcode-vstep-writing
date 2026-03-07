import FirebaseFirestore
import Foundation
import SwiftUI

// MARK: - Task Model
struct VSTEPTask: Identifiable, Codable {
    @DocumentID var id: String?
    let taskId: String
    let name: String
    let description: String
    let minWords: Int
    let timeLimit: Int
    let taskType: String

    enum CodingKeys: String, CodingKey {
        case taskId, name, description, minWords, timeLimit, taskType
    }
}

// MARK: - Question Model
struct VSTEPQuestion: Identifiable, Codable {
    @DocumentID var id: String?
    let questionId: String
    let taskType: String
    let category: String
    let title: String
    let situation: String?
    let task: String?
    let topic: String?
    let instruction: String?
    let requirements: [String]?
    let formalityLevel: String?
    let essayType: String?
    let difficulty: String
    var tags: [String]
    let suggestedStructure: [String]?

    // Computed from taskType - Firestore does not store these
    var isTask1: Bool { taskType == "task1" }
    var isTask2: Bool { taskType == "task2" }
    var minWords: Int { isTask1 ? 120 : 250 }
    var timeLimit: Int { isTask1 ? 20 : 40 }

    enum CodingKeys: String, CodingKey {
        case questionId, taskType, category, title, situation
        case task, topic, instruction, requirements, formalityLevel, essayType
        case difficulty, tags, suggestedStructure
        // minWords and timeLimit excluded - they are computed, not stored
    }
}

// MARK: - Rubric Model
struct VSTEPRubric: Identifiable, Codable {
    @DocumentID var id: String?
    let name: String
    let totalCriteria: Int
    let criteria: [String: RubricCriterion]

    enum CodingKeys: String, CodingKey {
        case name, totalCriteria, criteria
    }
}

struct RubricCriterion: Codable {
    let name: String
    let weight: Double
    let levels: [String: RubricLevel]
}

struct RubricLevel: Codable {
    let score: Int
    let descriptor: String
}

// MARK: - Submission Status
enum SubmissionStatus: String, Codable {
    case draft = "draft"
    case submitted = "submitted"
    case grading = "grading"
    case graded = "graded"
    case failed = "failed"

    var displayText: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .grading: return "Grading…"
        case .graded: return "Graded"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .draft: return "doc"
        case .submitted: return "paperplane.fill"
        case .grading: return "clock.fill"
        case .graded: return "checkmark.seal.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

// MARK: - User Submission
struct UserSubmission: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var questionId: String
    let content: String
    let wordCount: Int
    var submittedAt: Date
    var score: Double?
    var feedback: String?
    var overallComment: String?
    var suggestions: [String]?
    var criteria: [SubmissionCriterion]?
    var status: SubmissionStatus
    var essayText: String? = nil

    enum CodingKeys: String, CodingKey {
        case questionId, content, wordCount, submittedAt
        case score, feedback, overallComment, suggestions
        case criteria, status, essayText
    }
}

struct SubmissionCriterion: Codable, Hashable {
    let name: String
    let score: Double?
    let band: String?
    let feedback: String?
}

// MARK: - User Progress
struct UserProgress: Codable {
    var completedQuestions: [String]
    var averageScore: Double
    var totalSubmissions: Int
    var lastActivityDate: Date?
    var task1Completed: Int
    var task2Completed: Int
}

// MARK: - Plan Benefits
struct PlanBenefits: Codable {
    let unlimitedTests: Bool
    let aiGrammarCheck: Bool
    let detailedAnalytics: Bool
    let offlineMode: Bool
    let prioritySupport: Bool
    let adsRemoved: Bool

    // Safe decode - fallback when Firebase field is missing
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unlimitedTests =
            try container.decodeIfPresent(Bool.self, forKey: .unlimitedTests)
            ?? false
        aiGrammarCheck =
            try container.decodeIfPresent(Bool.self, forKey: .aiGrammarCheck)
            ?? true
        detailedAnalytics =
            try container.decodeIfPresent(Bool.self, forKey: .detailedAnalytics)
            ?? false
        offlineMode =
            try container.decodeIfPresent(Bool.self, forKey: .offlineMode)
            ?? false
        prioritySupport =
            try container.decodeIfPresent(Bool.self, forKey: .prioritySupport)
            ?? false
        adsRemoved =
            try container.decodeIfPresent(Bool.self, forKey: .adsRemoved)
            ?? false
    }
}

// MARK: - Plan Limits
struct PlanLimits: Codable {
    let gradingAttemptsPerEssay: Int
    let maxEssaysPerDay: Int
    let chatbotQuestionsPerDay: Int
    let submissionsPerEssayPerDay: Int

    // Fallback defaults when Firebase has not loaded yet
    static let freeFallback = PlanLimits(
        gradingAttemptsPerEssay: 1,
        maxEssaysPerDay: 2,
        chatbotQuestionsPerDay: 0,
        submissionsPerEssayPerDay: 1
    )

    static let advancedFallback = PlanLimits(
        gradingAttemptsPerEssay: 3,
        maxEssaysPerDay: 3,
        chatbotQuestionsPerDay: 10,
        submissionsPerEssayPerDay: 3
    )

    static let premierFallback = PlanLimits(
        gradingAttemptsPerEssay: 5,
        maxEssaysPerDay: 5,
        chatbotQuestionsPerDay: 50,
        submissionsPerEssayPerDay: 5
    )

    // Safe decode - fallback when Firebase field is missing
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gradingAttemptsPerEssay =
            try c.decodeIfPresent(Int.self, forKey: .gradingAttemptsPerEssay)
            ?? 1
        maxEssaysPerDay =
            try c.decodeIfPresent(Int.self, forKey: .maxEssaysPerDay) ?? 2
        chatbotQuestionsPerDay =
            try c.decodeIfPresent(Int.self, forKey: .chatbotQuestionsPerDay)
            ?? 0
        submissionsPerEssayPerDay =
            try c.decodeIfPresent(Int.self, forKey: .submissionsPerEssayPerDay)
            ?? 1
    }

    init(
        gradingAttemptsPerEssay: Int,
        maxEssaysPerDay: Int,
        chatbotQuestionsPerDay: Int,
        submissionsPerEssayPerDay: Int
    ) {
        self.gradingAttemptsPerEssay = gradingAttemptsPerEssay
        self.maxEssaysPerDay = maxEssaysPerDay
        self.chatbotQuestionsPerDay = chatbotQuestionsPerDay
        self.submissionsPerEssayPerDay = submissionsPerEssayPerDay
    }
}

// MARK: - Plan (IAP)
struct Plan: Codable, Identifiable {
    @DocumentID var id: String?
    let displayName: String
    let benefits: PlanBenefits
    let limits: PlanLimits?  // Optional: free plan only has limits, no benefits

    enum CodingKeys: String, CodingKey {
        case displayName, benefits, limits
    }
}

// MARK: - Daily Usage
struct DailyUsage: Codable {
    var gradingAttemptsPerEssay: [String: Int]  // questionId -> count
    var totalEssaysGradedToday: Int
    var chatbotQuestionsToday: Int
    var submissionsPerEssay: [String: Int]  // questionId -> count

    static let empty = DailyUsage(
        gradingAttemptsPerEssay: [:],
        totalEssaysGradedToday: 0,
        chatbotQuestionsToday: 0,
        submissionsPerEssay: [:]
    )
}

// MARK: - Usage Check Result
enum UsageCheckResult {
    case allowed
    case denied(reason: String)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    var deniedReason: String? {
        if case .denied(let reason) = self { return reason }
        return nil
    }
}

// MARK: - Firebase Service Error
enum FirebaseServiceError: LocalizedError {
    case notAuthenticated
    case documentNotFound
    case invalidData
    case encodingFailed
    case uploadFailed
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please sign in to continue."
        case .documentNotFound: return "Requested data not found."
        case .invalidData: return "Invalid data format."
        case .encodingFailed: return "Failed to encode data."
        case .uploadFailed: return "Upload failed."
        case .networkError: return "Network connection error."
        }
    }
}

// MARK: - Avatar Upload Error
enum AvatarUploadError: LocalizedError {
    case noCurrentUser
    case imageCompressionFailed
    case uploadFailed(Error)
    case downloadURLFailed(Error)
    case firestoreUpdateFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noCurrentUser:
            return "No authenticated user found."
        case .imageCompressionFailed:
            return "Failed to compress image data."
        case .uploadFailed(let error):
            return "Upload failed: \(error.localizedDescription)"
        case .downloadURLFailed(let error):
            return "Failed to get download URL: \(error.localizedDescription)"
        case .firestoreUpdateFailed(let error):
            return "Failed to update profile: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Models
struct PolicyInfo: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let type: PolicyType
}

enum PolicyType: String, Identifiable {
    case termsOfUse = "Terms of Use"
    case privacyPolicy = "Privacy Policy"
    var id: String { rawValue }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Biometric Auth Error
enum BiometricError: LocalizedError {
    case notAvailable
    case notEnrolled
    case failed(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device."
        case .notEnrolled:
            return
                "No biometric data enrolled. Please set up Face ID in Settings."
        case .failed(let error):
            return error.localizedDescription
        case .cancelled:
            return "Authentication was cancelled."
        }
    }
}

// MARK: - Biometric Type
enum BiometricType {
    case faceID
    case touchID
    case none
}

// MARK: - Chat Models
enum MessageRole: String {
    case user = "user"
    case model = "model"
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// Codable representation for Firestore storage
struct ChatMessageRecord: Codable {
    let id: String
    let role: String
    let content: String
    let timestamp: Date

    init(from message: ChatMessage) {
        self.id = message.id.uuidString
        self.role = message.role.rawValue
        self.content = message.content
        self.timestamp = message.timestamp
    }

    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: UUID(uuidString: id) ?? UUID(),
            role: MessageRole(rawValue: role) ?? .model,
            content: content,
            timestamp: timestamp
        )
    }
}

struct ChatSession: Codable, Identifiable {
    @DocumentID var id: String?
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessageRecord]
}

// MARK: - AI Chat Error
enum AIChatError: LocalizedError {
    case invalidResponseFormat
    case unauthenticated
    case serverBusy
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponseFormat:
            return "Could not parse AI response. Please try again."
        case .unauthenticated:
            return "Your session has expired. Please sign in again."
        case .serverBusy:
            return "AI assistant is busy. Please try again in a moment."
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Markdown Block
// Represents a parsed block-level markdown element
enum MarkdownBlock {
    case paragraph(String)
    case numberedItem(Int, String)
    case bulletItem(String, Int)
    case spacer
}
