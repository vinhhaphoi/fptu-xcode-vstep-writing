import FirebaseFirestore
import Foundation

extension FirebaseService {

    private static let freePlanID = "com.vstep.free"

    // MARK: - Fetch Single Plan (for IAP display purposes)
    func fetchPlan(productID: String) async -> Plan? {
        let doc = try? await db.collection("plans").document(productID)
            .getDocument()
        return try? doc?.data(as: Plan.self)
    }

    // MARK: - Fetch Multiple Plans (for IAP display purposes)
    func fetchPlans(productIDs: [String]) async -> [String: Plan] {
        var result: [String: Plan] = [:]
        await withTaskGroup(of: (String, Plan?).self) { group in
            for id in productIDs {
                group.addTask {
                    let plan = await self.fetchPlan(productID: id)
                    return (id, plan)
                }
            }
            for await (id, plan) in group {
                if let plan { result[id] = plan }
            }
        }
        return result
    }

    // MARK: - Fetch All Plan Limits from settings/subscription_plans
    // Quota source per Cloud Functions v3.0 — single document fetch
    // Returns [productID: PlanLimits] keyed by com.vstep.* product IDs
    // Field mapping from settings document:
    //   aiGradingPerDay          -> gradingAttemptsPerEssay (used for AI grading daily count)
    //   chatsPerDay              -> chatbotQuestionsPerDay
    //   analyticsPerWeek         -> insightRefreshesPerWeek
    //   essaysPerDay             -> maxEssaysPerDay
    //   submissionsPerEssayPerDay -> submissionsPerEssayPerDay
    func fetchAllPlanLimits() async -> [String: PlanLimits] {
        let snap =
            try? await db
            .collection("settings")
            .document("subscription_plans")
            .getDocument()

        guard let data = snap?.data() else {
            print("[FirebaseService] fetchAllPlanLimits: fallback to defaults")
            return fallbackPlanLimits()
        }

        var result: [String: PlanLimits] = [:]

        // Map server tier keys to product IDs
        let tierToProductID: [String: String] = [
            "advanced": "com.vstep.advanced",
            "premier": "com.vstep.premier",
        ]

        for (tier, productID) in tierToProductID {
            guard let tierData = data[tier] as? [String: Any] else { continue }

            // aiGradingPerDay is the new primary field for grading quota
            // gradingAttemptsPerEssay kept as fallback for backward compatibility
            let gradingPerDay =
                tierData["aiGradingPerDay"] as? Int
                ?? tierData["gradingAttemptsPerEssay"] as? Int
                ?? 3

            result[productID] = PlanLimits(
                maxEssaysPerDay: tierData["essaysPerDay"] as? Int ?? 0,
                gradingAttemptsPerEssay: gradingPerDay,
                submissionsPerEssayPerDay: tierData["submissionsPerEssayPerDay"]
                    as? Int ?? 3,
                chatbotQuestionsPerDay: tierData["chatsPerDay"] as? Int ?? 0,
                insightRefreshesPerWeek: tierData["analyticsPerWeek"] as? Int
                    ?? 0
            )
        }

        // Free plan stays client-side default — not managed by server
        result[Self.freePlanID] = .freeFallback

        return result.isEmpty ? fallbackPlanLimits() : result
    }

    // MARK: - Private: Fallback when Firestore unavailable
    private func fallbackPlanLimits() -> [String: PlanLimits] {
        [
            "com.vstep.free": .freeFallback,
            "com.vstep.advanced": .advancedFallback,
            "com.vstep.premier": .premierFallback,
        ]
    }
}
