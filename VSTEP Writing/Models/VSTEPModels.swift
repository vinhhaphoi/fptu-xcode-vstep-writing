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

    var isTask1: Bool { taskType == "task1" }
    var isTask2: Bool { taskType == "task2" }
    var minWords: Int { isTask1 ? 120 : 250 }
    var timeLimit: Int { isTask1 ? 20 : 40 }

    enum CodingKeys: String, CodingKey {
        case questionId, taskType, category, title, situation
        case task, topic, instruction, requirements, formalityLevel, essayType
        case difficulty, tags, suggestedStructure
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
    let maxEssaysPerDay: Int
    let gradingAttemptsPerEssay: Int
    let submissionsPerEssayPerDay: Int
    let chatbotQuestionsPerDay: Int
    let insightRefreshesPerWeek: Int

    // MARK: - Fallbacks
    static let freeFallback = PlanLimits(
        maxEssaysPerDay: 1,
        gradingAttemptsPerEssay: 1,
        submissionsPerEssayPerDay: 1,
        chatbotQuestionsPerDay: 0,
        insightRefreshesPerWeek: 0
    )

    static let advancedFallback = PlanLimits(
        maxEssaysPerDay: 5,
        gradingAttemptsPerEssay: 3,
        submissionsPerEssayPerDay: 3,
        chatbotQuestionsPerDay: 20,
        insightRefreshesPerWeek: 3
    )

    static let premierFallback = PlanLimits(
        maxEssaysPerDay: .max,
        gradingAttemptsPerEssay: .max,
        submissionsPerEssayPerDay: .max,
        chatbotQuestionsPerDay: 100,
        insightRefreshesPerWeek: 5
    )

    // Safe decode — fallback when Firebase field is missing
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxEssaysPerDay =
            try c.decodeIfPresent(Int.self, forKey: .maxEssaysPerDay) ?? 2
        gradingAttemptsPerEssay =
            try c.decodeIfPresent(Int.self, forKey: .gradingAttemptsPerEssay)
            ?? 1
        submissionsPerEssayPerDay =
            try c.decodeIfPresent(Int.self, forKey: .submissionsPerEssayPerDay)
            ?? 1
        chatbotQuestionsPerDay =
            try c.decodeIfPresent(Int.self, forKey: .chatbotQuestionsPerDay)
            ?? 0
        insightRefreshesPerWeek =
            try c.decodeIfPresent(Int.self, forKey: .insightRefreshesPerWeek)
            ?? 0
    }

    init(
        maxEssaysPerDay: Int,
        gradingAttemptsPerEssay: Int,
        submissionsPerEssayPerDay: Int,
        chatbotQuestionsPerDay: Int,
        insightRefreshesPerWeek: Int
    ) {
        self.maxEssaysPerDay = maxEssaysPerDay
        self.gradingAttemptsPerEssay = gradingAttemptsPerEssay
        self.submissionsPerEssayPerDay = submissionsPerEssayPerDay
        self.chatbotQuestionsPerDay = chatbotQuestionsPerDay
        self.insightRefreshesPerWeek = insightRefreshesPerWeek
    }
}

// MARK: - Plan (IAP)
struct Plan: Codable, Identifiable {
    @DocumentID var id: String?
    let displayName: String
    let benefits: PlanBenefits
    let limits: PlanLimits?

    enum CodingKeys: String, CodingKey {
        case displayName, benefits, limits
    }
}

// MARK: - Daily Usage
struct DailyUsage: Codable {
    var gradingAttemptsPerEssay: [String: Int]
    var totalEssaysGradedToday: Int
    var chatbotQuestionsToday: Int
    var submissionsPerEssay: [String: Int]

    static let empty = DailyUsage(
        gradingAttemptsPerEssay: [:],
        totalEssaysGradedToday: 0,
        chatbotQuestionsToday: 0,
        submissionsPerEssay: [:]
    )
}

// MARK: - Weekly Insight Usage
struct WeeklyInsightUsage {
    var weekKey: String
    var usedCount: Int

    static let empty = WeeklyInsightUsage(weekKey: "", usedCount: 0)
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
enum MarkdownBlock {
    case paragraph(String)
    case numberedItem(Int, String)
    case bulletItem(String, Int)
    case spacer
}

// MARK: - Analytics Models

struct UserProgressInsights: Codable {
    let overallInsight: String
    let strengths: [String]
    let weaknesses: [String]
    let recommendations: [ProgressRecommendation]
    let nextGoal: String
    let trendLabel: TrendLabel

    enum TrendLabel: String, Codable {
        case improving, stable, declining

        var icon: String {
            switch self {
            case .improving: return "arrow.up.right.circle.fill"
            case .stable: return "arrow.right.circle.fill"
            case .declining: return "arrow.down.right.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .improving: return .green
            case .stable: return BrandColor.medium
            case .declining: return .red
            }
        }

        var label: String {
            switch self {
            case .improving: return "Improving"
            case .stable: return "Stable"
            case .declining: return "Declining"
            }
        }
    }
}

struct ProgressRecommendation: Codable, Identifiable {
    var id: String { area }
    let area: String
    let tip: String
}

struct AnalyzeProgressResponse: Codable {
    let insights: UserProgressInsights
    let cached: Bool
    let updatedAt: String?
    let usedCount: Int?
    let weeklyLimit: Int?
    let weekKey: String?
}

struct AnalyticsProgress: Equatable {
    let step: Int
    let total: Int
    let label: String

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(step) / Double(total)
    }
}

// MARK: - VSTEP Rank Model

struct VSTEPRank: Identifiable {
    let id: String
    let cefr: String
    let displayName: String
    let color: Color
    let difficulties: [String]
    let taskCategories: [TaskCategory]

    struct TaskCategory {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let taskType: String
    }
}

// MARK: - AIUsageError
enum AIUsageError: LocalizedError {
    case permissionDenied(message: String)
    case failedPrecondition(message: String)
    case resourceExhausted(message: String)
    case unauthenticated(message: String)
    case invalidArgument(message: String)
    case invalidResponse
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let m),
            .failedPrecondition(let m),
            .resourceExhausted(let m),
            .unauthenticated(let m),
            .invalidArgument(let m),
            .unknown(let m):
            return m
        case .invalidResponse:
            return "Invalid response from server."
        }
    }
}

extension VSTEPRank {
    static let allRanks: [VSTEPRank] = [
        VSTEPRank(
            id: "b1",
            cefr: "B1",
            displayName: "Pre-Intermediate",
            color: .blue,
            difficulties: ["easy"],
            taskCategories: [
                TaskCategory(
                    title: "Task 1 - Visual Description",
                    subtitle: "Describe a chart, graph or table",
                    icon: "chart.bar",
                    color: .blue,
                    taskType: "task1"
                ),
                TaskCategory(
                    title: "Task 2 - Opinion Essay",
                    subtitle: "Give your opinion on a familiar topic",
                    icon: "text.bubble",
                    color: .indigo,
                    taskType: "task2"
                ),
            ]
        ),
        VSTEPRank(
            id: "b2",
            cefr: "B2",
            displayName: "Upper-Intermediate",
            color: .purple,
            difficulties: ["medium"],
            taskCategories: [
                TaskCategory(
                    title: "Task 1 - Data Analysis",
                    subtitle: "Analyse trends and compare data",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple,
                    taskType: "task1"
                ),
                TaskCategory(
                    title: "Task 2 - Argumentative Essay",
                    subtitle: "Argue both sides of a complex issue",
                    icon: "text.book.closed",
                    color: .orange,
                    taskType: "task2"
                ),
            ]
        ),
        VSTEPRank(
            id: "c1",
            cefr: "C1",
            displayName: "Advanced",
            color: .red,
            difficulties: ["hard"],
            taskCategories: [
                TaskCategory(
                    title: "Task 1 - Complex Visuals",
                    subtitle: "Synthesise data from multiple charts",
                    icon: "chart.pie",
                    color: .red,
                    taskType: "task1"
                ),
                TaskCategory(
                    title: "Task 2 - Critical Essay",
                    subtitle: "Evaluate ideas with advanced vocabulary",
                    icon: "doc.richtext",
                    color: .pink,
                    taskType: "task2"
                ),
            ]
        ),
    ]
}
