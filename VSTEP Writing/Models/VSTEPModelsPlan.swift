// MARK: - Plan Limits
// Updated fallback values match new subscription tier definitions:
//   Advanced: 3 AI gradings/day, 30 chats/day, 3 insights/week
//   Premier:  5 AI gradings/day, 50 chats/day, 5 insights/week
//   Free:     0 for all AI features — Normal grading queue only

struct PlanLimits: Codable {
    let maxEssaysPerDay: Int
    let gradingAttemptsPerEssay: Int
    let submissionsPerEssayPerDay: Int
    let chatbotQuestionsPerDay: Int
    let insightRefreshesPerWeek: Int

    // Free: no AI access — only Normal grading queue available
    static let freeFallback = PlanLimits(
        maxEssaysPerDay: 0,
        gradingAttemptsPerEssay: 0,
        submissionsPerEssayPerDay: 0,
        chatbotQuestionsPerDay: 0,
        insightRefreshesPerWeek: 0
    )

    // Advanced: 3 AI gradings/day, 30 chat/day, 3 insights/week
    static let advancedFallback = PlanLimits(
        maxEssaysPerDay: 3,
        gradingAttemptsPerEssay: 3,
        submissionsPerEssayPerDay: 3,
        chatbotQuestionsPerDay: 30,
        insightRefreshesPerWeek: 3
    )

    // Premier: 5 AI gradings/day, 50 chat/day, 5 insights/week, priority support
    static let premierFallback = PlanLimits(
        maxEssaysPerDay: 5,
        gradingAttemptsPerEssay: 5,
        submissionsPerEssayPerDay: 5,
        chatbotQuestionsPerDay: 50,
        insightRefreshesPerWeek: 5
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxEssaysPerDay =
            try c.decodeIfPresent(Int.self, forKey: .maxEssaysPerDay) ?? 0
        gradingAttemptsPerEssay =
            try c.decodeIfPresent(Int.self, forKey: .gradingAttemptsPerEssay)
            ?? 0
        submissionsPerEssayPerDay =
            try c.decodeIfPresent(Int.self, forKey: .submissionsPerEssayPerDay)
            ?? 0
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
