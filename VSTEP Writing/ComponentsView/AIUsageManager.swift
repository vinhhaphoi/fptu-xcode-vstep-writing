import Foundation
import Observation

// MARK: - AIUsageManager
@Observable
class AIUsageManager {

    static let shared = AIUsageManager()

    // MARK: - State
    var dailyUsage: DailyUsage = .empty
    var planLimits: [String: PlanLimits] = [:]
    var isLoading: Bool = false

    private init() {}

    // MARK: - Load Initial Data (call on app start)
    func loadInitialData() async {
        async let usageTask: () = loadTodayUsage()
        async let limitsTask: () = loadPlanLimits()
        await usageTask
        await limitsTask
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

    // MARK: - Resolve Limits
    // Always reads from Firebase first, falls back to hardcoded defaults
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

        // Free tier: also guard total unique essays submitted
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

    // MARK: - Record Actions (call after successful operation)
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

    // MARK: - Remaining Helpers (for UI display)
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
}
