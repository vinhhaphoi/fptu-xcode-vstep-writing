import Foundation
import Observation

// MARK: - AIUsageManager
@Observable
class AIUsageManager {

    static let shared = AIUsageManager()

    // MARK: - State
    var dailyUsage: DailyUsage = .empty
    var weeklyInsightUsage: WeeklyInsightUsage = .empty
    var planLimits: [String: PlanLimits] = [:]
    var isLoading: Bool = false

    private init() {}

    // MARK: - Load Initial Data
    func loadInitialData() async {
        async let usageTask: () = loadTodayUsage()
        async let limitsTask: () = loadPlanLimits()
        async let weeklyTask: () = loadWeeklyInsightUsage()
        await usageTask
        await limitsTask
        await weeklyTask
    }

    // MARK: - Load Plan Limits from Firebase
    func loadPlanLimits() async {
        let fetched = await FirebaseService.shared.fetchAllPlanLimits()
        await MainActor.run {
            planLimits = fetched
            print(
                "[AIUsageManager] Loaded \(fetched.count) plan limits from Firebase"
            )
        }
    }

    // MARK: - Load Today Usage
    func loadTodayUsage() async {
        isLoading = true
        do {
            let usage = try await FirebaseService.shared.fetchTodayUsage()
            await MainActor.run { dailyUsage = usage }
        } catch {
            print(
                "[AIUsageManager] Load usage error: \(error.localizedDescription)"
            )
        }
        isLoading = false
    }

    // MARK: - Load Weekly Insight Usage
    func loadWeeklyInsightUsage() async {
        do {
            let usage = try await FirebaseService.shared
                .fetchWeeklyInsightUsage()
            await MainActor.run { weeklyInsightUsage = usage }
        } catch {
            print(
                "[AIUsageManager] Load weekly insight error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Resolve Limits
    func limits(for store: StoreKitManager) -> PlanLimits {
        if store.isPurchased("com.vstep.premier") {
            return planLimits["com.vstep.premier"] ?? .premierFallback
        }
        if store.isPurchased("com.vstep.advanced") {
            return planLimits["com.vstep.advanced"] ?? .advancedFallback
        }
        return planLimits["com.vstep.free"] ?? .freeFallback
    }

    // MARK: - Check AI Grading
    func canGrade(questionId: String, store: StoreKitManager)
        -> UsageCheckResult
    {
        let limits = limits(for: store)
        let attemptsForEssay =
            dailyUsage.gradingAttemptsPerEssay[questionId] ?? 0
        let isNewEssay = dailyUsage.gradingAttemptsPerEssay[questionId] == nil

        if isNewEssay
            && dailyUsage.totalEssaysGradedToday >= limits.maxEssaysPerDay
        {
            return .denied(
                reason:
                    "You've reached the daily limit of \(limits.maxEssaysPerDay) essays."
            )
        }
        if attemptsForEssay >= limits.gradingAttemptsPerEssay {
            return .denied(
                reason:
                    "You've used all \(limits.gradingAttemptsPerEssay) AI grading attempts for this essay today."
            )
        }
        return .allowed
    }

    // MARK: - Check Submission
    func canSubmit(questionId: String, store: StoreKitManager)
        -> UsageCheckResult
    {
        let limits = limits(for: store)
        let submissionsForEssay =
            dailyUsage.submissionsPerEssay[questionId] ?? 0

        if submissionsForEssay >= limits.submissionsPerEssayPerDay {
            return .denied(
                reason:
                    "You've reached the submission limit for this essay today."
            )
        }

        if !store.isPurchased("com.vstep.advanced")
            && !store.isPurchased("com.vstep.premier")
        {
            let uniqueEssaysSubmitted = dailyUsage.submissionsPerEssay.keys
                .count
            if uniqueEssaysSubmitted >= limits.maxEssaysPerDay
                && submissionsForEssay == 0
            {
                return .denied(
                    reason:
                        "Free users can submit up to \(limits.maxEssaysPerDay) essays per day."
                )
            }
        }
        return .allowed
    }

    // MARK: - Check Chatbot
    func canUseChatbot(store: StoreKitManager) -> UsageCheckResult {
        let limits = limits(for: store)
        if limits.chatbotQuestionsPerDay == 0 {
            return .denied(
                reason:
                    "Chatbot is available for Advanced and Premier subscribers only."
            )
        }
        if dailyUsage.chatbotQuestionsToday >= limits.chatbotQuestionsPerDay {
            return .denied(
                reason:
                    "You've used all \(limits.chatbotQuestionsPerDay) chatbot questions for today."
            )
        }
        return .allowed
    }

    // MARK: - Check Insight Refresh (weekly quota)
    func canRefreshInsights(store: StoreKitManager) -> UsageCheckResult {
        let limits = limits(for: store)

        // Free tier: no access
        if limits.insightRefreshesPerWeek == 0 {
            return .denied(
                reason: "AI Insights require Advanced or Premier subscription."
            )
        }

        // Reset count if new week
        let currentWeek = Self.isoWeekKey()
        let effectiveUsed =
            weeklyInsightUsage.weekKey == currentWeek
            ? weeklyInsightUsage.usedCount
            : 0

        if effectiveUsed >= limits.insightRefreshesPerWeek {
            return .denied(
                reason:
                    "Weekly limit of \(limits.insightRefreshesPerWeek) insight refreshes reached. Resets Monday."
            )
        }
        return .allowed
    }

    // MARK: - Record Actions

    func recordGrading(questionId: String) async {
        do {
            try await FirebaseService.shared.incrementGradingAttempt(
                for: questionId
            )
            await loadTodayUsage()
        } catch {
            print(
                "[AIUsageManager] Record grading error: \(error.localizedDescription)"
            )
        }
    }

    func recordSubmission(questionId: String) async {
        do {
            try await FirebaseService.shared.incrementSubmission(
                for: questionId
            )
            await loadTodayUsage()
        } catch {
            print(
                "[AIUsageManager] Record submission error: \(error.localizedDescription)"
            )
        }
    }

    func recordChatbotQuestion() async {
        do {
            try await FirebaseService.shared.incrementChatbotQuestion()
            await loadTodayUsage()
        } catch {
            print(
                "[AIUsageManager] Record chatbot error: \(error.localizedDescription)"
            )
        }
    }

    // Called after Gemini successfully returns fresh insights
    func recordInsightRefresh() async {
        do {
            let currentWeek = Self.isoWeekKey()
            try await FirebaseService.shared.incrementInsightRefresh(
                weekKey: currentWeek
            )
            await loadWeeklyInsightUsage()
        } catch {
            print(
                "[AIUsageManager] Record insight refresh error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Remaining Helpers

    func remainingGrading(for questionId: String, store: StoreKitManager) -> Int
    {
        let used = dailyUsage.gradingAttemptsPerEssay[questionId] ?? 0
        return max(0, limits(for: store).gradingAttemptsPerEssay - used)
    }

    func remainingChatbot(store: StoreKitManager) -> Int {
        max(
            0,
            limits(for: store).chatbotQuestionsPerDay
                - dailyUsage.chatbotQuestionsToday
        )
    }

    func remainingEssays(store: StoreKitManager) -> Int {
        max(
            0,
            limits(for: store).maxEssaysPerDay
                - dailyUsage.totalEssaysGradedToday
        )
    }

    func remainingInsightRefreshes(store: StoreKitManager) -> Int {
        let limit = limits(for: store).insightRefreshesPerWeek
        let currentWeek = Self.isoWeekKey()
        let used =
            weeklyInsightUsage.weekKey == currentWeek
            ? weeklyInsightUsage.usedCount
            : 0
        return max(0, limit - used)
    }

    // MARK: - ISO Week Key Helper
    static func isoWeekKey(from date: Date = .now) -> String {
        let cal = Calendar(identifier: .iso8601)
        let week = cal.component(.weekOfYear, from: date)
        let year = cal.component(.yearForWeekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }
}
