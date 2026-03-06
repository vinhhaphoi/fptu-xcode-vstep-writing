import Foundation
import LocalAuthentication

// MARK: - Biometric Auth Service
final class BiometricAuthService {

    static let shared = BiometricAuthService()
    private init() {}

    private let context = LAContext()

    // MARK: - Check device biometric support
    var biometricType: BiometricType {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    var isAvailable: Bool { biometricType != .none }

    // MARK: - Authenticate with biometrics + passcode fallback
    func authenticate(reason: String = "Sign in to your account") async throws {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error { throw BiometricError.failed(error) }
            throw BiometricError.notAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if !success { throw BiometricError.cancelled }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                throw BiometricError.cancelled
            case .biometryNotEnrolled:
                throw BiometricError.notEnrolled
            default:
                throw BiometricError.failed(laError)
            }
        }
    }
}
