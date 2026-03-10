import Combine
import Foundation
import SwiftUI
import WatchConnectivity

enum WatchSyncState {
    case waiting
    case synced
}

// Mirrors ChartDataPoint.dotColor logic from iOS ScoreView
struct ScoreEntry: Identifiable {
    let id = UUID()
    let index: Int
    let score: Double
    let date: Date
    let taskType: String?

    var dotColor: Color {
        switch taskType {
        case "task1": return BrandColor.light
        case "task2": return BrandColor.medium
        default: return BrandColor.primary
        }
    }
}

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    @Published var syncState: WatchSyncState = .waiting
    @Published var displayName: String = "Learner"
    @Published var averageScore: Double? = nil
    @Published var recentTopics: [String] = []
    @Published var recentScores: [Double] = []
    @Published var totalSubmissions: Int = 0
    @Published var task1Count: Int = 0
    @Published var task2Count: Int = 0
    @Published var scoreHistory: [ScoreEntry] = []

    override private init() {
        super.init()
    }

    func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendMessage(_ message: [String: Any]) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(message, replyHandler: nil)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        DispatchQueue.main.async { self.parseMessage(message) }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async { self.parseMessage(applicationContext) }
    }

    private func parseMessage(_ message: [String: Any]) {
        if let name = message[WatchMessageKeys.displayName] as? String {
            self.displayName = name
        }
        if let avg = message[WatchMessageKeys.averageScore] as? Double {
            self.averageScore = avg
        }
        if let topics = message[WatchMessageKeys.recentTopics] as? [String] {
            self.recentTopics = topics
        }
        if let scores = message[WatchMessageKeys.recentScores] as? [Double] {
            self.recentScores = scores
        }
        if let total = message[WatchMessageKeys.totalSubmissions] as? Int {
            self.totalSubmissions = total
        }
        if let t1 = message[WatchMessageKeys.task1Count] as? Int {
            self.task1Count = t1
        }
        if let t2 = message[WatchMessageKeys.task2Count] as? Int {
            self.task2Count = t2
        }
        if let scores = message[WatchMessageKeys.scoreHistory] as? [Double],
            let timestamps = message[WatchMessageKeys.scoreHistoryDates]
                as? [Double],
            let taskTypes = message[WatchMessageKeys.scoreHistoryTaskTypes]
                as? [String]
        {
            self.scoreHistory = zip(zip(scores, timestamps), taskTypes)
                .enumerated()
                .map { index, pair in
                    ScoreEntry(
                        index: index + 1,
                        score: pair.0.0,
                        date: Date(timeIntervalSince1970: pair.0.1),
                        taskType: pair.1
                    )
                }
        }
        self.syncState = .synced
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
}
