import FirebaseFirestore
import Foundation

extension FirebaseService {

    private static let freePlanID = "com.vstep.free"

    // MARK: - Fetch Single Plan
    func fetchPlan(productID: String) async -> Plan? {
        let doc = try? await db.collection("plans").document(productID)
            .getDocument()
        return try? doc?.data(as: Plan.self)
    }

    // MARK: - Fetch Multiple Plans (parallel)
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

    // MARK: - Fetch All Plans including free limits
    // Returns [productID: PlanLimits] for all plans including free
    func fetchAllPlanLimits() async -> [String: PlanLimits] {
        let allIDs = [
            "com.vstep.free", "com.vstep.advanced", "com.vstep.premier",
        ]
        var result: [String: PlanLimits] = [:]

        await withTaskGroup(of: (String, PlanLimits?).self) { group in
            for id in allIDs {
                group.addTask {
                    let doc = try? await self.db.collection("plans").document(
                        id
                    ).getDocument()
                    let limits = try? doc?.data()?["limits"].flatMap {
                        try? Firestore.Decoder().decode(
                            PlanLimits.self,
                            from: $0
                        )
                    }
                    return (id, limits)
                }
            }
            for await (id, limits) in group {
                if let limits { result[id] = limits }
            }
        }
        return result
    }
}
