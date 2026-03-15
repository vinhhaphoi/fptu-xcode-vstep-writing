import Combine
import Foundation
import WatchConnectivity

class SessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = SessionManager()

    @Published var receivedMessage: [String: Any] = [:]

    override private init() {
        super.init()
    }

    func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Send data from iOS to Watch
    func sendMessage(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else {
            print("[SessionManager] Session not activated yet")
            return
        }
        print("[WC] isPaired=\(WCSession.default.isPaired)")
        print("[WC] isWatchAppInstalled=\(WCSession.default.isWatchAppInstalled)")
        print("[WC] activationState=\(WCSession.default.activationState.rawValue)")
        print("[WC] isReachable=\(WCSession.default.isReachable)")


        if WCSession.default.isReachable {
            // Watch dang mo - gui truc tiep
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print(
                    "[SessionManager] sendMessage error: \(error.localizedDescription)"
                )
                // Fallback neu gui truc tiep that bai
                try? WCSession.default.updateApplicationContext(message)
            }
        } else {
            // Watch dang tat man hinh - luu vao context, Watch nhan khi mo lai
            do {
                try WCSession.default.updateApplicationContext(message)
                print("[SessionManager] Context updated successfully")
            } catch {
                print(
                    "[SessionManager] updateApplicationContext error: \(error.localizedDescription)"
                )
            }
        }
    }

    // Receive data from Watch
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.receivedMessage = message
        }
    }

    // iOS-only required delegates
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
