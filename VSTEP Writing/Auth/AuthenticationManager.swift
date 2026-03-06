import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import GoogleSignIn
import SwiftUI

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var user: User?
    @Published var authState: AuthState = .loading

    private var authStateListener: AuthStateDidChangeListenerHandle?

    enum AuthState {
        case loading
        case authenticated
        case unauthenticated
    }

    private init() {
        setupAuthStateListener()
    }

    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.authState = user != nil ? .authenticated : .unauthenticated
        }
    }

    // MARK: - Email/Password Auth
    func signUp(
        email: String,
        password: String,
        displayName: String,
        targetLevel: String
    ) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)

        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = displayName
        try await changeRequest.commitChanges()

        try await saveUserProfile(
            userId: result.user.uid,
            displayName: displayName,
            targetLevel: targetLevel
        )
    }

    private func saveUserProfile(
        userId: String,
        displayName: String,
        targetLevel: String
    ) async throws {
        let db = Firestore.firestore()
        try await db.collection("users").document(userId).setData([
            "displayName": displayName,
            "targetLevel": targetLevel,
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.user = result.user
    }

    // MARK: - Google Sign-In
    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.noClientID
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootViewController = windowScene.windows.first?.rootViewController
        else {
            throw AuthError.noRootViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        let user = result.user

        guard let idToken = user.idToken?.tokenString else {
            throw AuthError.noIDToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: user.accessToken.tokenString
        )

        let authResult = try await Auth.auth().signIn(with: credential)
        self.user = authResult.user
    }

    // MARK: - Sign Out
    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        self.user = nil

        // Reset biometric unlock state on sign out
        isBiometricLoginEnabled = false
    }

    // MARK: - Delete Account
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "Auth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No user logged in"]
            )
        }
        let db = Firestore.firestore()
        try await db.collection("users").document(user.uid).delete()
        try await user.delete()
    }

    // MARK: - Custom Errors
    enum AuthError: LocalizedError {
        case noClientID
        case noRootViewController
        case noIDToken
        case signInFailed(String)

        var errorDescription: String? {
            switch self {
            case .noClientID: return "Client ID not found"
            case .noRootViewController: return "Root View Controller not found"
            case .noIDToken: return "Can not get ID Token"
            case .signInFailed(let message): return message
            }
        }
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}

// MARK: - Biometric Login Preference
extension AuthenticationManager {

    private static let biometricEnabledKey = "isBiometricLoginEnabled"

    // Persist Face ID preference in UserDefaults
    var isBiometricLoginEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.biometricEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.biometricEnabledKey) }
    }

    // Returns true if device supports biometric AND user has not enabled it yet
    // Call this after first login success to decide whether to show the prompt
    func shouldPromptEnableBiometric() -> Bool {
        guard BiometricAuthService.shared.isAvailable else { return false }
        return !isBiometricLoginEnabled
    }
}
