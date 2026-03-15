import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

// MARK: - AnalyticsManager

@MainActor
final class AnalyticsManager: ObservableObject {

    static let shared = AnalyticsManager()

    @Published var insights: UserProgressInsights? = nil
    @Published var isFetching: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isCached: Bool = false
    @Published var cachedAt: String? = nil
    @Published var analysisProgress: AnalyticsProgress? = nil
    @Published var autoRefresh: Bool = false {
        didSet {
            guard oldValue != autoRefresh else { return }
            saveAutoRefreshPreference()
        }
    }

    private var activeFetchTask: Task<Void, Never>? = nil
    private var progressListener: ListenerRegistration? = nil
    private let firestore = Firestore.firestore()

    init() {
        Task { await loadAutoRefreshPreference() }
        Task { await loadCachedInsights() }
    }

    // MARK: - Start Progress Listener

    private func startProgressListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = firestore
            .collection("users").document(uid)
            .collection("insights").document("insights")

        progressListener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            guard
                let data = snapshot?.data(),
                let progressMap = data["progress"] as? [String: Any],
                let step  = progressMap["step"]  as? Int,
                let total = progressMap["total"] as? Int,
                let label = progressMap["label"] as? String
            else {
                self.analysisProgress = nil
                return
            }
            self.analysisProgress = AnalyticsProgress(step: step, total: total, label: label)
        }
    }

    // MARK: - Stop Progress Listener

    private func stopProgressListener() {
        progressListener?.remove()
        progressListener = nil
        analysisProgress = nil
    }

    // MARK: - Load Insights
    // Server enforces quota — no client-side check needed

    func loadInsights(forceRefresh: Bool = false) {
        guard !isFetching, activeFetchTask == nil else { return }

        isFetching = true
        errorMessage = nil
        startProgressListener()

        activeFetchTask = Task {
            defer {
                self.isFetching = false
                self.activeFetchTask = nil
                self.stopProgressListener()
            }

            do {
                let response = try await AIUsageManager.shared.analyzeUserProgress(
                    forceRefresh: forceRefresh
                )

                self.insights  = response.insights
                self.isCached  = response.cached
                self.cachedAt  = response.updatedAt

                // Sync quota từ server sau khi nhận response thành công
                await AIUsageManager.shared.syncUsageFromServer()

            } catch let error as AIUsageError {
                switch error {
                case .failedPrecondition: self.errorMessage = "needmoresubmissions"
                case .resourceExhausted:  self.errorMessage = "quotaexceeded"
                case .permissionDenied:   self.errorMessage = "notsubscribed"
                case .unauthenticated:    self.errorMessage = "notloggedin"
                default:
                    self.errorMessage = error.localizedDescription
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Trigger Auto Refresh

    func triggerAutoRefreshIfEnabled() {
        guard autoRefresh else { return }
        loadInsights(forceRefresh: false)
    }

    // MARK: - Load Cached Insights

    func loadCachedInsights() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let snap = try? await firestore
            .collection("users").document(uid)
            .collection("insights").document("insights")
            .getDocument()

        guard
            let data = snap?.data(),
            let insightsMap = data["insights"] as? [String: Any]
        else { return }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: insightsMap)
            let decoded  = try JSONDecoder().decode(UserProgressInsights.self, from: jsonData)
            self.insights  = decoded
            self.isCached  = data["cached"] as? Bool ?? true
            if let ts = data["updatedAt"] as? Timestamp {
                self.cachedAt = ISO8601DateFormatter().string(from: ts.dateValue())
            } else if let tsStr = data["updatedAt"] as? String {
                self.cachedAt = tsStr
            }
        } catch {
            // Cache decode failed — not critical
        }
    }

    // MARK: - AutoRefresh Preference

    private func saveAutoRefreshPreference() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        firestore
            .collection("users").document(uid)
            .collection("insights").document("insightUsage")
            .setData(["autoRefresh": autoRefresh], merge: true)
    }

    private func loadAutoRefreshPreference() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snap = try? await firestore
            .collection("users").document(uid)
            .collection("insights").document("insightUsage")
            .getDocument()
        self.autoRefresh = snap?.data()?["autoRefresh"] as? Bool ?? false
    }
}
