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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questionId = try c.decode(String.self, forKey: .questionId)
        taskType = try c.decodeIfPresent(String.self, forKey: .taskType) ?? "task1"
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "General"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Question"
        situation = try c.decodeIfPresent(String.self, forKey: .situation)
        task = try c.decodeIfPresent(String.self, forKey: .task)
        topic = try c.decodeIfPresent(String.self, forKey: .topic)
        instruction = try c.decodeIfPresent(String.self, forKey: .instruction)
        requirements = try c.decodeIfPresent([String].self, forKey: .requirements)
        formalityLevel = try c.decodeIfPresent(String.self, forKey: .formalityLevel)
        essayType = try c.decodeIfPresent(String.self, forKey: .essayType)
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty) ?? "easy"
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        suggestedStructure = try c.decodeIfPresent([String].self, forKey: .suggestedStructure)
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

    struct RubricCriterion: Codable {
        let name: String
        let weight: Double
        let levels: [String: RubricLevel]
    }

    struct RubricLevel: Codable {
        let score: Int
        let descriptor: String
    }
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
    var userId: String?
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
    var gradingMethod: GradingMethod = .normal
    var priority: SubmissionPriority = .normal
    var assignedTeacherId: String? = nil
    var assignedTeacherEmail: String? = nil
    var gradedBy: String? = nil
    var gradedByName: String? = nil
    var gradedAt: Date? = nil
    var errorMessage: String? = nil

    enum CodingKeys: String, CodingKey {
        // Note: 'id' is intentionally excluded — @DocumentID handles it
        case userId, questionId, content, wordCount, submittedAt
        case score, feedback, overallComment, suggestions
        case criteria, status, essayText
        case gradingMethod, priority, assignedTeacherId, assignedTeacherEmail, gradedBy, gradedByName, gradedAt, errorMessage
    }

    // Manual memberwise initializer (since adding init(from:) removes the synthesized one)
    init(
        id: String? = nil,
        userId: String? = nil,
        questionId: String,
        content: String,
        wordCount: Int,
        submittedAt: Date = Date(),
        score: Double? = nil,
        feedback: String? = nil,
        overallComment: String? = nil,
        suggestions: [String]? = nil,
        criteria: [SubmissionCriterion]? = nil,
        status: SubmissionStatus = .submitted,
        essayText: String? = nil,
        gradingMethod: GradingMethod = .normal,
        priority: SubmissionPriority = .normal,
        assignedTeacherId: String? = nil,
        assignedTeacherEmail: String? = nil,
        gradedBy: String? = nil,
        gradedByName: String? = nil,
        gradedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.questionId = questionId
        self.content = content
        self.wordCount = wordCount
        self.submittedAt = submittedAt
        self.score = score
        self.feedback = feedback
        self.overallComment = overallComment
        self.suggestions = suggestions
        self.criteria = criteria
        self.status = status
        self.essayText = essayText
        self.gradingMethod = gradingMethod
        self.priority = priority
        self.assignedTeacherId = assignedTeacherId
        self.assignedTeacherEmail = assignedTeacherEmail
        self.gradedBy = gradedBy
        self.gradedByName = gradedByName
        self.gradedAt = gradedAt
        self.errorMessage = errorMessage
    }

    // Custom decoder: uses decodeIfPresent for newer fields so that
    // old Firestore documents (which don't have these fields) can still
    // be decoded without throwing "data couldn't be read because it is missing".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Core required fields (always present)
        userId       = try c.decodeIfPresent(String.self, forKey: .userId)
        questionId   = try c.decode(String.self,          forKey: .questionId)
        content      = try c.decode(String.self,          forKey: .content)
        wordCount    = try c.decode(Int.self,             forKey: .wordCount)
        submittedAt  = try c.decode(Date.self,            forKey: .submittedAt)
        status       = try c.decode(SubmissionStatus.self, forKey: .status)

        // Optional score / feedback fields
        score           = try c.decodeIfPresent(Double.self,              forKey: .score)
        feedback        = try c.decodeIfPresent(String.self,              forKey: .feedback)
        overallComment  = try c.decodeIfPresent(String.self,              forKey: .overallComment)
        suggestions     = try c.decodeIfPresent([String].self,            forKey: .suggestions)
        criteria        = try c.decodeIfPresent([SubmissionCriterion].self, forKey: .criteria)
        essayText       = try c.decodeIfPresent(String.self,              forKey: .essayText)

        // Newer fields — fall back to defaults so old documents decode safely
        gradingMethod       = try c.decodeIfPresent(GradingMethod.self,      forKey: .gradingMethod)  ?? .normal
        priority            = try c.decodeIfPresent(SubmissionPriority.self, forKey: .priority)       ?? .normal
        assignedTeacherId   = try c.decodeIfPresent(String.self,             forKey: .assignedTeacherId)
        assignedTeacherEmail = try c.decodeIfPresent(String.self,            forKey: .assignedTeacherEmail)
        gradedBy            = try c.decodeIfPresent(String.self,             forKey: .gradedBy)
        gradedByName        = try c.decodeIfPresent(String.self,             forKey: .gradedByName)
        gradedAt            = try c.decodeIfPresent(Date.self,               forKey: .gradedAt)
        errorMessage        = try c.decodeIfPresent(String.self,             forKey: .errorMessage)
    }
}

// MARK: - Submission Criterion

struct SubmissionCriterion: Codable, Hashable {
    let name: String
    let score: Double?
    let band: String?
    let feedback: String?
    let comment: String? // Added to match web app
}

// MARK: - Question Attempt Group

struct QuestionAttemptGroup: Identifiable, Hashable {
    var id: String { questionId }
    let questionId: String
    let question: VSTEPQuestion?
    let attempts: [UserSubmission]

    static func == (lhs: QuestionAttemptGroup, rhs: QuestionAttemptGroup)
        -> Bool
    {
        lhs.questionId == rhs.questionId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(questionId)
    }

    var latestAttempt: UserSubmission { attempts[0] }
    var previousAttempts: [UserSubmission] { Array(attempts.dropFirst()) }
    var attemptCount: Int { attempts.count }
    var bestScore: Double? { attempts.compactMap(\.score).max() }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    var id: String { submission.id ?? UUID().uuidString }
    let submission: UserSubmission
    let taskType: String?

    var score: Double { submission.score ?? 0 }
    var date: Date { submission.submittedAt }

    var dotColor: Color {
        switch taskType {
        case "task1": return BrandColor.light
        case "task2": return BrandColor.medium
        default: return BrandColor.primary
        }
    }
}

// MARK: - User Stats

struct UserStats: Codable {
    var averageScore: Double = 0.0
    var totalSubmissions: Int = 0
    var task1Count: Int = 0
    var task2Count: Int = 0
    var completedQuestions: [String] = []
    var lastCalculatedAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case averageScore, totalSubmissions, task1Count, task2Count
        case completedQuestions, lastCalculatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        averageScore = try c.decodeIfPresent(Double.self, forKey: .averageScore) ?? 0.0
        totalSubmissions = try c.decodeIfPresent(Int.self, forKey: .totalSubmissions) ?? 0
        task1Count = try c.decodeIfPresent(Int.self, forKey: .task1Count) ?? 0
        task2Count = try c.decodeIfPresent(Int.self, forKey: .task2Count) ?? 0
        completedQuestions = try c.decodeIfPresent([String].self, forKey: .completedQuestions) ?? []
        lastCalculatedAt = try c.decodeIfPresent(String.self, forKey: .lastCalculatedAt)
    }

    // Default init for manual creation
    init(
        averageScore: Double = 0.0,
        totalSubmissions: Int = 0,
        task1Count: Int = 0,
        task2Count: Int = 0,
        completedQuestions: [String] = [],
        lastCalculatedAt: String? = nil
    ) {
        self.averageScore = averageScore
        self.totalSubmissions = totalSubmissions
        self.task1Count = task1Count
        self.task2Count = task2Count
        self.completedQuestions = completedQuestions
        self.lastCalculatedAt = lastCalculatedAt
    }
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
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unlimitedTests =
            try c.decodeIfPresent(Bool.self, forKey: .unlimitedTests) ?? false
        aiGrammarCheck =
            try c.decodeIfPresent(Bool.self, forKey: .aiGrammarCheck) ?? true
        detailedAnalytics =
            try c.decodeIfPresent(Bool.self, forKey: .detailedAnalytics)
            ?? false
        offlineMode =
            try c.decodeIfPresent(Bool.self, forKey: .offlineMode) ?? false
        prioritySupport =
            try c.decodeIfPresent(Bool.self, forKey: .prioritySupport) ?? false
        adsRemoved =
            try c.decodeIfPresent(Bool.self, forKey: .adsRemoved) ?? false
    }
}

// MARK: - Plan Limits

struct PlanLimits: Codable {
    let maxEssaysPerDay: Int
    let gradingAttemptsPerEssay: Int
    let submissionsPerEssayPerDay: Int
    let chatbotQuestionsPerDay: Int
    let insightRefreshesPerWeek: Int

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
        case .noCurrentUser: return "No authenticated user found."
        case .imageCompressionFailed: return "Failed to compress image data."
        case .uploadFailed(let e):
            return "Upload failed: \(e.localizedDescription)"
        case .downloadURLFailed(let e):
            return "Failed to get download URL: \(e.localizedDescription)"
        case .firestoreUpdateFailed(let e):
            return "Failed to update profile: \(e.localizedDescription)"
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

    enum PolicyType: String, Identifiable {
        case termsOfUse    = "Terms of Use"
        case privacyPolicy = "Privacy Policy"
        var id: String { rawValue }
    }
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
        case .failed(let e): return e.localizedDescription
        case .cancelled: return "Authentication was cancelled."
        }
    }
}

enum BiometricType { case faceID, touchID, none }

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
        case .unknown(let m): return m
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
}

struct TaskCategory {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let taskType: String
}

// MARK: - Grading Method

enum GradingMethod: String, Codable {
    case quick = "quick"
    case ai = "ai"
    case normal = "normal"

    var displayName: String {
        switch self {
        case .quick: return "Quick Grading"
        case .ai: return "AI Grading"
        case .normal: return "Normal Queue"
        }
    }

    var icon: String {
        switch self {
        case .quick: return "bolt.fill"
        case .ai: return "sparkles"
        case .normal: return "clock.fill"
        }
    }

    var description: String {
        switch self {
        case .quick: return "Priority queue — teacher or AI grades immediately"
        case .ai: return "Graded by Gemini AI within 30 seconds"
        case .normal:
            return "Joins the pool — graded when a teacher is available"
        }
    }
}

// MARK: - Submission Priority

enum SubmissionPriority: String, Codable {
    case high = "high"
    case normal = "normal"
}

// MARK: - AI Usage Error

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

// MARK: - VSTEP Rank Data

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
